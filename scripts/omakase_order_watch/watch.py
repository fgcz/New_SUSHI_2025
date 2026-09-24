#!/usr/bin/env python3
"""OMAKASE trigger: notice when a B-Fabric order's status becomes `processed`.

`processed` is the agreed trigger. It means the data is available: a member of
staff finishes QC and sets the order's status by hand. Nothing downstream reacts
to that today, and this script is the first thing that does.

**It detects and records. It never submits anything.** Choosing a pipeline and
proposing it to a bioinformatician are later stages; this one exists so those
stages have something to consume.

Set reconciliation, not sampling
--------------------------------
Every tick asks B-Fabric for the *complete* set of orders whose status is
`processed`, and subtracts the set this watcher has already handled. That
distinction matters, because the usual objection to polling -- that a change can
fall between two looks -- applies to asking "what changed since I last looked?"
and does not apply here:

* Being down loses nothing. Off for a day, the next tick still sees everything.
  The truth lives in B-Fabric; this is not a queue that can drop messages.
* The watermark is our own handled-set, not a timestamp, so there is no clock
  skew and no "since" boundary to get wrong. (B-Fabric has no
  `statusmodifiedafter` filter anyway -- only `modifiedafter`.)
* The whole set is small. Measured on production 2026-09-10: **30 orders**, and
  the id-only query took **0.6-2.1 s** across four runs.

Being polite to the B-Fabric server
-----------------------------------
The tick is one id-only query. Full records are fetched only for ids that are
new, batched into a single call. At the default 15-minute interval that is 96
queries a day, roughly a minute of B-Fabric time in total. The interval has a
hard floor, and a jitter so several instances cannot line up. On error the
watcher backs off instead of retrying immediately.

Read-only by construction: `client.read` is the only B-Fabric call in this file.

Profiles (2026-09-24)
--------------------
B-Fabric TEST and PRODUCTION are separate instances with separate order-id spaces, so the
watcher works for exactly one of them at a time: `--profile test` (the default, B-Fabric
TEST, paired with the fgcz-h-083 backend) or `--profile production` (B-Fabric PRODUCTION,
paired with fgcz-h-082). Each keeps its state and events under ~/.omakase/<profile>/, and
both files record `env`; a state file from the other instance, or one that does not say, is
refused. See omakase_core/profile.py.

Usage:
    python watch.py --once                         # one tick on B-Fabric TEST, then exit
    python watch.py --profile production --seed    # adopt production's backlog, emit nothing
    python watch.py --profile production           # loop at the default interval
    python watch.py --interval 1800                # every 30 minutes
    python watch.py --status                       # what has been seen so far

Requires bfabricPy (present in gi_py3.12.8) and ~/.bfabricpy.yml.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from bfabric import Bfabric

if __package__ in (None, ""):  # `python watch.py` as well as `-m omakase_order_watch.watch`
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from omakase_core import profile as P  # noqa: E402

TRIGGER_STATUS = "processed"

# Below this the query stops being a considerate use of a shared server. The
# event is a human setting a status by hand, so minutes of latency cost nothing.
MIN_INTERVAL_SECONDS = 300
# One hour, agreed with the user on 2026-09-10 as sufficient: a person sets the
# status by hand and a bioinformatician approval follows, so detection latency of
# an hour costs nothing, and this is 24 queries a day against a shared server.
DEFAULT_INTERVAL_SECONDS = 3600

# A tick that suddenly sees more new orders than this stops and asks for a human.
# It means the status vocabulary changed, the state file was lost, or --seed was
# never run -- and in every one of those cases firing a burst of events is wrong.
DEFAULT_MAX_NEW = 10

# Order fields carried into an event. Enough for the pipeline-choice stage to do
# its work, and no free-text customer fields: order records are FGCZ `internal`.
EVENT_FIELDS = [
    "id",
    "status",
    "statusmodified",
    "statusmodifiedby",
    "modified",
    "created",
    "project",
    "servicetype",
    "technology",
    "sequencingapplication",
    "instrument",
    "libraryprotocol",
    "numberofsamples",
    "countsamples",
    "countdatasets",
]

_stop = False


def _on_signal(signum, _frame):
    global _stop
    _stop = True
    print(f"\n[watch] signal {signum} received, finishing the current tick", file=sys.stderr)


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def log(msg: str) -> None:
    print(f"[{now_iso()}] {msg}", flush=True)


# --------------------------------------------------------------------- state


def load_state(path: Path, prof: P.Profile) -> dict:
    """The handled-set for one B-Fabric instance. Raises P.EnvMismatch for any other."""
    if not path.exists():
        return {"version": 1, "env": prof.bfabric_env, "seeded_at": None,
                "handled": {}, "ticks": 0}
    with path.open(encoding="utf-8") as fh:
        state = json.load(fh)
    # Reconciling one instance's processed-set against the other's handled-set would call
    # every order new, or -- worse -- call a new one already handled because an id collides.
    P.check_env(state.get("env"), prof, f"state file {path}")
    state.setdefault("handled", {})
    state.setdefault("ticks", 0)
    return state


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2, sort_keys=True)
    os.chmod(tmp, 0o600)
    tmp.replace(path)  # atomic, so a crash mid-write cannot corrupt the watermark


# --------------------------------------------------------------------- B-Fabric


def build_query(projects: list[int] | None) -> dict:
    query: dict = {"status": TRIGGER_STATUS}
    if projects:
        # Confirmed working 2026-09-10: {"status": ..., "projectid": N}
        query["projectid"] = projects if len(projects) > 1 else projects[0]
    return query


def current_ids(client: Bfabric, query: dict) -> tuple[set[int], float]:
    """The complete set of order ids currently at the trigger status."""
    t0 = time.time()
    rows = client.read("order", query, max_results=None, return_id_only=True)
    return {int(r["id"]) for r in rows}, time.time() - t0


def fetch_orders(client: Bfabric, ids: list[int]) -> list[dict]:
    """One batched call, not one call per order."""
    if not ids:
        return []
    return list(client.read("order", {"id": sorted(ids)}, max_results=None))


# --------------------------------------------------------------------- events


def write_event(events_dir: Path, order: dict, env: str) -> Path:
    events_dir.mkdir(parents=True, exist_ok=True)
    oid = int(order["id"])
    payload = {
        "schema": "omakase.order_processed.v1",
        # Which B-Fabric instance the order id belongs to. omakase_core refuses to ingest
        # an event without it, or from the instance its profile does not pair with.
        "env": env,
        "detected_at": now_iso(),
        "trigger_status": TRIGGER_STATUS,
        "order": {k: order.get(k) for k in EVENT_FIELDS},
    }
    path = events_dir / f"order_{oid}.json"
    with path.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True, default=str)
    os.chmod(path, 0o600)
    return path


# --------------------------------------------------------------------- the tick


def tick(client, state, query, events_dir, max_new, dry_run, seed=False) -> int:
    """One reconciliation. Returns the number of new orders acted on."""
    ids, seconds = current_ids(client, query)
    known = {int(k) for k in state["handled"]}
    new = sorted(ids - known)
    gone = sorted(known - ids)

    state["ticks"] = state.get("ticks", 0) + 1
    state["last_tick"] = now_iso()
    state["last_query_seconds"] = round(seconds, 3)
    state["last_set_size"] = len(ids)

    log(f"tick: {len(ids)} order(s) at status={TRIGGER_STATUS} "
        f"({seconds:.2f}s) | known {len(known)} | new {len(new)} | left the set {len(gone)}")

    if gone:
        # Not an error and not something to act on: an order can move on. Recorded
        # because status churn is worth seeing before anyone trusts this trigger.
        log(f"  note: order(s) no longer {TRIGGER_STATUS}: {gone}")
        state.setdefault("left_the_set", {})[now_iso()] = gone

    if seed:
        for oid in new:
            state["handled"][str(oid)] = {"seeded": True, "first_seen": now_iso()}
        state["seeded_at"] = now_iso()
        log(f"  seeded {len(new)} existing order(s) as already handled; no events written")
        return 0

    if not new:
        return 0

    if len(new) > max_new:
        log(f"  STOP: {len(new)} new orders in one tick exceeds --max-new {max_new}. "
            f"Nothing was written. Run --seed if this is a first run, or investigate.")
        raise SystemExit(3)

    orders = {int(o["id"]): o for o in fetch_orders(client, new)}
    for oid in new:
        order = orders.get(oid)
        if order is None:
            log(f"  ! order {oid} was in the id set but could not be read; leaving it unhandled")
            continue
        if dry_run:
            log(f"  DRY RUN would emit event for order {oid} "
                f"(statusmodified={order.get('statusmodified')})")
            continue
        path = write_event(events_dir, order, state["env"])
        state["handled"][str(oid)] = {
            "first_seen": now_iso(),
            "statusmodified": order.get("statusmodified"),
            "statusmodifiedby": (order.get("statusmodifiedby") or {}).get("id"),
            "event": str(path),
        }
        log(f"  NEW order {oid} -> {path.name} (statusmodified={order.get('statusmodified')})")
    return len(new)


# --------------------------------------------------------------------- cli


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--profile", choices=sorted(P.PROFILES), default=None,
                    help=f"which B-Fabric instance + backend pair (default $OMAKASE_PROFILE, "
                         f"else {P.DEFAULT})")
    ap.add_argument("--env", default=None, choices=["PRODUCTION", "TEST"],
                    help="kept for old command lines; must agree with the profile or the "
                         "run is refused")
    ap.add_argument("--interval", type=int, default=DEFAULT_INTERVAL_SECONDS,
                    help=f"seconds between ticks (floor {MIN_INTERVAL_SECONDS})")
    ap.add_argument("--once", action="store_true", help="one tick, then exit")
    ap.add_argument("--seed", action="store_true",
                    help="mark everything currently processed as handled and exit")
    ap.add_argument("--status", action="store_true", help="print the state file and exit")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would happen; write no events and no state")
    ap.add_argument("--project", type=int, action="append", default=None,
                    help="restrict to a project id (repeatable)")
    ap.add_argument("--max-new", type=int, default=DEFAULT_MAX_NEW)
    ap.add_argument("--state", type=Path, default=None,
                    help="default ~/.omakase/<profile>/order_watch_state.json")
    ap.add_argument("--events", type=Path, default=None,
                    help="default ~/.omakase/<profile>/events")
    args = ap.parse_args()

    prof = P.get(args.profile)
    if args.env and args.env != prof.bfabric_env:
        print(f"refused: --env {args.env} contradicts profile {prof.name!r} "
              f"(B-Fabric {prof.bfabric_env}); pass --profile instead", file=sys.stderr)
        return 2
    args.state = args.state or prof.state_path
    args.events = args.events or prof.events_dir
    try:
        state = load_state(args.state, prof)
    except P.EnvMismatch as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return 2

    if args.status:
        handled = state.get("handled", {})
        print(f"profile        : {prof.name} (B-Fabric {prof.bfabric_env}, backend {prof.backend})")
        print(f"state file     : {args.state}")
        print(f"seeded at      : {state.get('seeded_at')}")
        print(f"ticks so far   : {state.get('ticks')}")
        print(f"last tick      : {state.get('last_tick')}")
        print(f"last query     : {state.get('last_query_seconds')}s over {state.get('last_set_size')} order(s)")
        print(f"handled orders : {len(handled)}")
        seeded = sum(1 for v in handled.values() if v.get("seeded"))
        print(f"  of which seeded (never emitted an event): {seeded}")
        return 0

    interval = max(args.interval, MIN_INTERVAL_SECONDS)
    if interval != args.interval:
        log(f"interval raised to the {MIN_INTERVAL_SECONDS}s floor")

    client = Bfabric.connect(config_file_env=prof.bfabric_env)
    query = build_query(args.project)
    log(f"profile={prof.name} env={prof.bfabric_env} query={query} "
        f"state={args.state} events={args.events}")

    if state.get("seeded_at") is None and not args.seed and not args.dry_run:
        log("WARNING: this state has never been seeded. The first tick will treat every "
            "order already at status=processed as new. Run --seed first unless that is "
            "what you want.")

    signal.signal(signal.SIGINT, _on_signal)
    signal.signal(signal.SIGTERM, _on_signal)

    backoff = interval
    while True:
        try:
            tick(client, state, query, args.events, args.max_new, args.dry_run, seed=args.seed)
            if not args.dry_run:
                save_state(args.state, state)
            backoff = interval
        except SystemExit:
            raise
        except Exception as exc:  # noqa: BLE001
            # Back off rather than hammer a server that is already unhappy.
            backoff = min(backoff * 2, 3600)
            log(f"  ! tick failed ({type(exc).__name__}: {exc}); next try in {backoff}s")

        if args.seed or args.once or _stop:
            return 0

        # Jitter so two instances, or a restart, cannot settle into lockstep.
        sleep_for = backoff * random.uniform(0.9, 1.1)
        log(f"  sleeping {sleep_for:.0f}s")
        slept = 0.0
        while slept < sleep_for and not _stop:
            time.sleep(min(5.0, sleep_for - slept))
            slept += 5.0
        if _stop:
            return 0


if __name__ == "__main__":
    sys.exit(main())
