#!/usr/bin/env python3
"""Named orders (--order): an event only for an order at `processed` now. rc 0 = all pass.

    python3 omakase_order_watch/test_watch.py

No network: B-Fabric is a fake client that answers `read("order", {"id": [...]})` from a
dict, and every file lives under a temporary OMAKASE_ROOT.
"""
from __future__ import annotations

import importlib
import io
import json
import os
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

ROOT = Path(tempfile.mkdtemp(prefix="omakase_watch_test_"))
os.environ["OMAKASE_ROOT"] = str(ROOT)
os.environ.pop("OMAKASE_PROFILE", None)

from omakase_core import profile as P  # noqa: E402
P = importlib.reload(P)                 # pick up the temporary root
from omakase_order_watch import watch as W  # noqa: E402
W.P = P

cases = 0


def case(name):
    global cases
    cases += 1
    print(f"  ok  {name}")


class FakeBfabric:
    def __init__(self, orders):
        self.orders = {o["id"]: o for o in orders}
        self.calls = 0

    def read(self, endpoint, query, max_results=None, return_id_only=False):
        assert endpoint == "order" and not return_id_only, (endpoint, query)
        self.calls += 1
        return [self.orders[i] for i in query["id"] if i in self.orders]


def order(oid, status="processed"):
    return {"id": oid, "status": status, "statusmodified": "2026-09-29 10:00:00",
            "project": {"id": 35611}, "servicetype": {"id": 5},
            "customer_free_text": "must never reach an event"}


def run(client, ids):
    out = io.StringIO()
    with redirect_stdout(out):
        rc = W.fetch_named(client, ids, events, "TEST")
    return rc, out.getvalue()


prof = P.get("test")
events = prof.events_dir
state = prof.state_path
state.parent.mkdir(parents=True, exist_ok=True)
state.write_text(json.dumps({"version": 1, "env": "TEST", "handled": {"1": {"seeded": True}}}))
state_before = state.read_bytes()

client = FakeBfabric([order(101), order(102, status="finished"), order(104)])

# --- a processed order gets an event, marked as named, allow-listed fields only
rc, out = run(client, [101])
ev = json.loads(W.event_path(events, 101).read_text())
assert rc == 0 and "NAMED order 101" in out, (rc, out)
assert ev["source"] == "named" and ev["env"] == "TEST" and ev["order"]["id"] == 101, ev
assert ev["schema"] == "omakase.order_processed.v1" and ev["trigger_status"] == "processed"
assert "customer_free_text" not in ev["order"], ev["order"]
assert oct(W.event_path(events, 101).stat().st_mode & 0o777) == "0o600"
case("a processed order gets an event: source named, env TEST, allow-listed fields, mode 600")

# --- anything not processed is declined, and nothing is written
rc, out = run(client, [102])
assert rc == 3 and "'finished', not 'processed'" in out, (rc, out)
assert not W.event_path(events, 102).exists()
case("an order that is not processed is DECLINED (rc 3), no event")

rc, out = run(client, [103])
assert rc == 3 and "not found in B-Fabric TEST" in out, (rc, out)
assert not W.event_path(events, 103).exists()
case("an order B-Fabric does not have is DECLINED (rc 3), no event")

# --- one batched read for several ids; one decline makes the rc 3, the rest still land
calls = client.calls
rc, out = run(client, [104, 102])
assert client.calls == calls + 1, "several ids must be ONE B-Fabric call"
assert rc == 3 and W.event_path(events, 104).exists() and not W.event_path(events, 102).exists()
case("several ids: one batched read; the processed one is written, rc 3 for the other")

# --- a real detection is never replaced; an earlier named copy is refreshed
W.write_event(events, order(105), "TEST")          # what a tick writes: source watcher
detected = W.event_path(events, 105).read_bytes()
client.orders[105] = order(105)
rc, out = run(client, [105])
assert rc == 0 and "already detected by the watcher" in out, (rc, out)
assert W.event_path(events, 105).read_bytes() == detected
case("an event the watcher wrote is kept as it is")

legacy = {"schema": "omakase.order_processed.v1", "env": "TEST", "detected_at": "x",
          "order": {"id": 106}}                       # written before `source` existed
W.event_path(events, 106).write_text(json.dumps(legacy))
client.orders[106] = order(106)
rc, out = run(client, [106])
assert rc == 0 and json.loads(W.event_path(events, 106).read_text()) == legacy, out
case("an event with no `source` (written before 2026-09-29) counts as a detection, kept")

first = json.loads(W.event_path(events, 101).read_text())
client.orders[101]["statusmodified"] = "2026-09-29 11:00:00"
rc, out = run(client, [101])
again = json.loads(W.event_path(events, 101).read_text())
assert rc == 0 and again["order"]["statusmodified"] == "2026-09-29 11:00:00" != first["order"]["statusmodified"]
case("an earlier named event is refreshed from B-Fabric")

# --- the loop's state file is never touched
assert state.read_bytes() == state_before
case("the state file is byte-identical after every named fetch")

# --- the tick's own events now say where they came from
assert json.loads(W.event_path(events, 105).read_text())["source"] == "watcher"
case("an event written by a tick carries source watcher")


# --- the command line
def cli(*argv):
    r = subprocess.run([sys.executable, "-m", "omakase_order_watch.watch", *argv],
                       cwd=SCRIPTS, env=dict(os.environ), capture_output=True, text=True,
                       timeout=60)
    return r.returncode, r.stdout + r.stderr


for flag in ("--seed", "--ingest", "--status", "--once", "--dry-run"):
    rc, out = cli("--order", "1", flag)
    assert rc == 2 and "does not combine with " + flag in out, (flag, rc, out)
case("--order refuses --seed, --ingest, --status, --once and --dry-run (rc 2), before B-Fabric")

print(f"{cases} cases, all pass")
