#!/usr/bin/env python3
"""OMAKASE prototype — command line.

The first vertical slice of design v0.3 plus `docs/omakase-prototype-design-delta.md`:

    order event  ->  candidate  ->  [FIXED recipe]  ->  proposal  ->  human approves
                 ->  chain runner, one step at a time  ->  done or halted

Nothing here uses a model. Per design decision D4 the trigger, the timer and every state
transition are ordinary code.

    python -m omakase_core.omakase ingest  --event ~/.omakase/test/events/order_35773.json
    python -m omakase_core.omakase show
    python -m omakase_core.omakase show    --candidate 1
    python -m omakase_core.omakase approve --candidate 1 --actor masaomi
    python -m omakase_core.omakase run     --candidate 1 --dry-run
    python -m omakase_core.omakase run     --candidate 1

Every command works inside one profile (omakase_core/profile.py): `test` by default,
B-Fabric TEST paired with the fgcz-h-083 backend, files under ~/.omakase/test/. An event
from the other B-Fabric instance is refused at ingest, and `production` never submits.

Approval is explicit and human, every time. The deadline-driven auto-approval of design
v0.3 §10 is deliberately not in this slice.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

import yaml
from pathlib import Path

if __package__ in (None, ""):  # allow `python omakase.py` as well as `-m`
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    __package__ = "omakase_core"

from . import evidence, gate, input_dataset, recipes, reference, store as S  # noqa: E402
from . import constraints as K, match, notify, profile as P  # noqa: E402
from .runner import ChainRunner             # noqa: E402
from .sushi import SushiClient              # noqa: E402

# Store, events and backend come from the profile; the history audit is shared by both.
DEFAULT_HISTORY = P.HISTORY
MCP_JSON = Path("/srv/sushi/masa_test_new_sushi_20260527/.mcp.json")

# Order fields carried into the candidate. The allow-list of design v0.3 §3: billing,
# requester and order label are not among them, and never reach the store.
KEPT_ORDER_FIELDS = [
    "id", "status", "statusmodified", "statusmodifiedby", "project", "servicetype",
    "technology", "sequencingapplication", "instrument", "libraryprotocol",
    "numberofsamples", "countsamples", "countdatasets",
]


def token(prof: P.Profile | None = None) -> str:
    """The bearer for the profile's backend. Env first, then the MCP config, so no third
    copy exists. Called without a profile it means the default one."""
    name = (prof or P.get()).token_env
    tok = os.environ.get(name)
    if tok:
        return tok
    try:
        return json.load(MCP_JSON.open())["mcpServers"]["sushi-chain"]["env"][name]
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"no backend token: set {name} or make {MCP_JSON} readable ({exc})")


# ------------------------------------------------------------------------ commands


def cmd_ingest(args, st: S.Store) -> int:
    event = json.load(Path(args.event).open(encoding="utf-8"))
    # Before anything else: an order id only means something inside its own B-Fabric
    # instance, and this profile's backend holds datasets from exactly one of them.
    P.check_env(event.get("env"), args.prof, f"event {args.event}")
    order = event.get("order") or {}
    order_id = int(order["id"])
    dataset_id, found_by = _resolve_dataset(args, order)

    # Automatic selection needs the dataset: Species is a dataset column, not an order field.
    dataset = (None if args.recipe else
               SushiClient(args.base_url, token(args.prof)).dataset(dataset_id))
    recipe = recipes.select(order, args.recipe, dataset)
    print(f"recipe:   {recipe['id']}@{recipe['version']} "
          + ("(named)" if args.recipe else "(the one recipe whose match accepts this order)"))
    # Expand and check BEFORE a candidate exists, so a refused recipe leaves nothing behind.
    steps, derived = _resolve_steps(recipe, args, dataset_id, dataset)
    assessed = _assess(recipe, steps, args)
    refused = K.refusals(assessed)
    if refused:
        raise recipes.RecipeError(
            f"recipe {recipe['id']}@{recipe['version']} refuses this order - "
            f"{len(refused)} rule(s) fail on the parameters that would be submitted:\n  "
            + "\n  ".join(K.describe(i) for i in refused))
    # Deterministic, not random: the same order always lands in the same arm, so a rerun
    # cannot quietly move it. A control candidate is never proposed on, which is the only
    # way to later notice that OMAKASE has started influencing what people choose.
    arm = (S.ARM_CONTROL if args.control_every and order_id % args.control_every == 0
           else S.ARM_PROPOSE)
    cid, created = st.upsert_candidate(
        order_id=order_id,
        input_dataset_id=dataset_id,
        recipe_id=recipe["id"],
        recipe_version=str(recipe["version"]),
        project_number=(order.get("project") or {}).get("id"),
        arm=arm,
    )
    if not created:
        print(f"candidate {cid} already exists for order {order_id} / dataset "
              f"{dataset_id} / {recipe['id']}@{recipe['version']} — nothing to do")
        return 0

    st.set_order_params(cid, {k: order.get(k) for k in KEPT_ORDER_FIELDS if k in order})
    st.set_state(cid, S.PARAMS_OK, actor="omakase-core",
                 reason=f"allow-listed order fields recorded ({len(order)} available)")
    if arm == S.ARM_CONTROL:
        st.set_state(cid, S.SKIPPED, actor="omakase-core",
                     reason="control arm: deliberately not proposed on, so that what "
                            "people choose unaided stays observable")
        print(f"candidate {cid}: order {order_id} is in the CONTROL arm — no proposal made")
        return 0

    st.set_steps(cid, steps)
    st.set_checklist(cid, assessed)
    waiting = K.open_items(assessed)
    ev = _evidence_for(st, cid, order, args.history)
    st.set_state(cid, S.PROPOSED, actor="omakase-core",
                 reason=f"recipe {recipe['id']}@{recipe['version']}, "
                        f"{len(steps)} steps; {evidence.describe(ev)}"
                        + ("; " + "; ".join(derived) if derived else "")
                        + (f"; {len(waiting)} checklist item(s) await a person"
                           if waiting else ""))
    print(f"candidate {cid}: order {order_id}, dataset {dataset_id}, "
          f"recipe {recipe['id']}@{recipe['version']} -> PROPOSED")
    print(f"  input:    {found_by}")
    for note in derived:
        print(f"  derived: {note}")
    print(f"  evidence: {evidence.describe(ev)}")
    _print_candidate(st, cid)
    return 0


def _assess(recipe: dict, steps: list[dict], args) -> list[dict]:
    """The recipe's checklist evaluated on these steps. Defaults are fetched only if needed."""
    items = recipe.get("items") or []
    defaults: dict[str, dict | None] = {}
    if any(i["kind"] == K.MACHINE for i in items):
        client = SushiClient(args.base_url, token(args.prof))
        for app in sorted({st_["app_name"] for st_ in steps}):
            defaults[app] = client.app_defaults(app)
    return K.assess(items, steps, defaults)


def _resolve_dataset(args, order: dict) -> tuple[int, str]:
    """The SUSHI dataset this order's data lives in. Explicit wins; otherwise search.

    `--dataset` is kept, and not only as a fallback: when an order resolves to more than
    one raw dataset the answer is genuinely a human's, and there has to be a way to give it.
    """
    if args.dataset:
        return int(args.dataset), f"named on the command line (--dataset {args.dataset})"
    client = SushiClient(args.base_url, token(args.prof))
    project = (order.get("project") or {}).get("id")
    return input_dataset.resolve(client, project, int(order["id"]))


def _resolve_steps(recipe: dict, args, dataset_id: int,
                   dataset: dict | None = None) -> tuple[list[dict], list[str]]:
    """Expand the recipe's sentinels against the input dataset, before anyone approves.

    The dataset is only fetched when a sentinel is actually present, so the recipes that
    need nothing derived — `fastqc_only` — make no network call and keep working on a node
    that cannot reach the backend.
    """
    text = json.dumps(recipe["steps"])
    if recipes.FROM_SPECIES not in text and recipes.SAME_AS_PREVIOUS not in text:
        return recipe["steps"], []
    if dataset is None and recipes.needs_dataset(recipe["steps"]):
        dataset = SushiClient(args.base_url, token(args.prof)).dataset(dataset_id)
    return recipes.resolve_parameters(recipe["steps"], dataset, recipe["id"])


def _seqs(expr) -> set[int]:
    if isinstance(expr, dict):
        return ({expr["step"]} if "step" in expr else
                set().union(*[_seqs(v) for v in expr.values()] or [set()]))
    if isinstance(expr, list):
        return set().union(*[_seqs(v) for v in expr] or [set()])
    return set()


def _print_checklist(items: list[dict]) -> None:
    if not items:
        return
    print("  checklist:")
    for i in items:
        print("    " + K.describe(i))


def _evidence_for(st: S.Store, cid: int, order: dict, history_path) -> dict | None:
    """Counted frequency for the proposed chain. Returns None when nothing is known.

    No model is consulted. The number is a fraction with its denominator, because the
    measured top-1 over real analysis is 17% weighted and 8% for NGS -- a bare percentage
    from a model would be believed and would be wrong.
    """
    try:
        hist = evidence.History(history_path)
    except OSError:
        return None
    if not hist.by_service:
        return None
    st_id = (order.get("servicetype") or {}).get("id")
    if st_id is None:
        return None
    return hist.lookup(st_id, evidence.shape(st.steps(cid)))


def _print_candidate(st: S.Store, cid: int) -> None:
    cand = st.candidate(cid)
    print(f"\ncandidate {cid}  state={cand['state']}  order={cand['order_id']}  "
          f"dataset={cand['input_dataset_id']}  "
          f"recipe={cand['recipe_id']}@{cand['recipe_version']}")
    print("  proposed chain:")
    for step in st.steps(cid):
        dep = step["depends_on_seq"]
        src = f"output of step {dep}" if dep else f"dataset {cand['input_dataset_id']}"
        sub = st.latest_submission(cid, step["seq"])
        state = f"{sub['state']} (attempt {sub['attempt']})" if sub else "not submitted"
        print(f"    {step['seq']}. {step['app_name']:<16} on {src:<20} "
              f"{json.dumps(step['parameters'], sort_keys=True)}  [{state}]")
    _print_checklist(st.checklist(cid))
    subs = st.submissions(cid)
    if subs:
        print("  submissions:")
        for s in subs:
            print(f"    step {s['step_seq']} attempt {s['attempt']}: {s['state']:<10} "
                  f"jobs={s['sushi_job_ids_json']} out_ds={s['output_dataset_id']}")
    print("  transitions:")
    for t in st.transitions(cid):
        print(f"    {t['at']}  {str(t['from_state']):<12} -> {t['to_state']:<12} "
              f"{t['actor']:<12} {t['reason'] or ''}")


def cmd_show(args, st: S.Store) -> int:
    if args.candidate:
        _print_candidate(st, args.candidate)
        return 0
    rows = st.candidates(args.state)
    if not rows:
        print("no candidates")
        return 0
    print(f"{'id':>4}  {'state':<14} {'order':>7} {'dataset':>8}  recipe")
    for r in rows:
        print(f"{r['id']:>4}  {r['state']:<14} {r['order_id']:>7} "
              f"{r['input_dataset_id']:>8}  {r['recipe_id']}@{r['recipe_version']}")
    return 0


def _require_proposed(st: S.Store, cid: int):
    cand = st.candidate(cid)
    if cand is None:
        raise SystemExit(f"no candidate {cid}")
    if cand["state"] != S.PROPOSED:
        raise SystemExit(f"candidate {cid} is {cand['state']}, not PROPOSED")
    return cand


def cmd_approve(args, st: S.Store) -> int:
    """Accepted unchanged. The weakest of the three labels, and recorded as such."""
    _require_proposed(st, args.candidate)
    _require_confirmed_before_start(st, args.candidate)
    proposed = st.steps(args.candidate)
    st.record_verdict(args.candidate, S.VERDICT_ACCEPTED, args.actor,
                      proposed_steps=proposed, final_steps=proposed, note=args.reason)
    st.set_state(args.candidate, S.APPROVED, actor=args.actor,
                 reason=args.reason or "accepted unchanged")
    print(f"candidate {args.candidate} APPROVED unchanged by {args.actor} "
          f"(verdict ACCEPTED recorded)")
    return 0


def _require_confirmed_before_start(st: S.Store, cid: int) -> None:
    open_ = K.open_items(st.checklist(cid), None)
    if open_:
        raise recipes.RecipeError(
            f"candidate {cid} has {len(open_)} checklist item(s) a person must confirm before "
            f"the chain may start (omakase confirm --candidate {cid} --item N --actor you):\n  "
            + "\n  ".join(K.describe(i) for i in open_))


def cmd_confirm(args, st: S.Store) -> int:
    """A named person confirms open checklist items. Each confirmation is recorded."""
    items = st.checklist(args.candidate)
    targets = ([i["idx"] for i in K.open_items(items)] if args.all else args.item)
    if not targets:
        print(f"candidate {args.candidate}: nothing open to confirm")
        return 0
    for idx in targets:
        st.confirm_item(args.candidate, idx, args.actor, args.note)
        st.record_transition(args.candidate, st.candidate(args.candidate)["state"],
                             st.candidate(args.candidate)["state"], args.actor,
                             reason=f"checklist item {idx} confirmed"
                                    + (f": {args.note}" if args.note else ""))
    print(f"candidate {args.candidate}: {len(targets)} item(s) confirmed by {args.actor}")
    _print_checklist(st.checklist(args.candidate))
    return 0


def cmd_revise(args, st: S.Store) -> int:
    """Edited into shape, then approved. The most informative label of the three.

    An unchanged acceptance can mean "correct" or "not worth the effort to change".
    A chain someone edited says what they actually wanted, which is the label execution
    history alone can never supply.
    """
    _require_proposed(st, args.candidate)
    proposed = st.steps(args.candidate)
    with open(args.steps, encoding="utf-8") as fh:
        final = yaml.safe_load(fh)
    final = final["steps"] if isinstance(final, dict) and "steps" in final else final
    if not isinstance(final, list) or not final:
        raise SystemExit(f"{args.steps} must hold a list of steps, or a mapping with 'steps'")
    if all(isinstance(s, dict) and "app" in s for s in final):
        # Format v1 steps, as a recipe author writes them. Compiled and expanded exactly as a
        # recipe would be, so an edited chain is held to the same rules as a proposed one.
        errors = recipes._validate_steps(final)
        if errors:
            raise SystemExit("the revised steps are not valid format v1:\n  - "
                             + "\n  - ".join(errors))
        cand = st.candidate(args.candidate)
        final = recipes.compile_steps(final)
        if recipes.needs_dataset(final) or recipes.SAME_AS_PREVIOUS in json.dumps(final):
            dataset = (SushiClient(args.base_url, token(args.prof))
                       .dataset(int(cand["input_dataset_id"]))
                       if recipes.needs_dataset(final) else None)
            final, _ = recipes.resolve_parameters(final, dataset, cand["recipe_id"])
    # The recipe's rules hold for an edited chain exactly as for a proposed one. A rule is
    # tied to a step by position, so an edit that changes which app sits at a position a
    # rule names is refused rather than re-targeted by guesswork.
    cand = st.candidate(args.candidate)
    recipe = recipes.load(cand["recipe_id"], int(cand["recipe_version"])
                          if str(cand["recipe_version"]).isdigit() else None)
    was = {s_["seq"]: s_["app_name"] for s_ in recipe["steps"]}
    now = {s_["seq"]: s_["app_name"] for s_ in final}
    named = {i["at_step_seq"] for i in recipe["items"] if i["at_step_seq"]} | {
        seq for i in recipe["items"] if i.get("check") for seq in _seqs(i["check"])}
    moved = sorted(n for n in named if was.get(n) != now.get(n))
    if moved:
        raise recipes.RecipeError(
            f"the revision changes step(s) {moved}, which the recipe's rules refer to; "
            f"reject the proposal and name another recipe instead")
    assessed = _assess(recipe, final, args)
    refused = K.refusals(assessed)
    if refused:
        raise recipes.RecipeError(
            "the revised chain breaks the recipe's rules:\n  "
            + "\n  ".join(K.describe(i) for i in refused))
    st.set_steps(args.candidate, final)
    st.set_checklist(args.candidate, assessed)   # re-assessed; earlier confirmations reset
    _require_confirmed_before_start(st, args.candidate)
    st.record_verdict(args.candidate, S.VERDICT_EDITED, args.actor,
                      proposed_steps=proposed, final_steps=st.steps(args.candidate),
                      note=args.reason)
    st.set_state(args.candidate, S.APPROVED, actor=args.actor,
                 reason=args.reason or f"edited from {len(proposed)} to {len(final)} steps, "
                                       f"then approved")
    print(f"candidate {args.candidate} EDITED and APPROVED by {args.actor}")
    _print_candidate(st, args.candidate)
    return 0


def cmd_reject(args, st: S.Store) -> int:
    _require_proposed(st, args.candidate)
    st.record_verdict(args.candidate, S.VERDICT_REJECTED, args.actor,
                      proposed_steps=st.steps(args.candidate), note=args.reason)
    st.set_state(args.candidate, S.CANCELLED, actor=args.actor,
                 reason=args.reason or "rejected by a human")
    print(f"candidate {args.candidate} REJECTED by {args.actor}")
    return 0


def cmd_labels(args, st: S.Store) -> int:
    """What the loop has accumulated. Counts only -- no model, no prediction."""
    rows = st.verdicts()
    if not rows:
        print("no verdicts recorded yet")
    else:
        tally = {}
        for r in rows:
            tally[r["verdict"]] = tally.get(r["verdict"], 0) + 1
        total = len(rows)
        print(f"{total} verdict(s) recorded")
        for v in (S.VERDICT_ACCEPTED, S.VERDICT_EDITED, S.VERDICT_REJECTED):
            n = tally.get(v, 0)
            print(f"  {v:<9} {n:>4}/{total}  {n / total:>5.0%}")
        print("\n  an unchanged ACCEPTED is the weakest signal: it can mean 'correct' or")
        print("  'not worth changing'. EDITED says what was actually wanted.")
    arms = {}
    for c in st.candidates():
        arms[c["arm"]] = arms.get(c["arm"], 0) + 1
    print(f"\narms: " + ", ".join(f"{k}={v}" for k, v in sorted(arms.items())))
    if arms.get(S.ARM_CONTROL, 0) == 0:
        print("  WARNING: no control candidates. Without an arm that is never proposed on,")
        print("  a later measurement cannot tell science from OMAKASE's own influence.")
    return 0


def cmd_run(args, st: S.Store) -> int:
    if not args.prof.may_submit:
        # Phase 0 reads production and writes nothing anywhere. A dry run is refused too:
        # it still walks the state machine, and a RUNNING candidate there would be a lie.
        print(f"\nDECLINED: profile {args.prof.name!r} never submits "
              f"(B-Fabric {args.prof.bfabric_env} is read-only in phase 0)", file=sys.stderr)
        return 3
    client = SushiClient(args.base_url, token(args.prof), dry_run=args.dry_run)
    runner = ChainRunner(st, client, max_retries=args.max_retries)
    cid = args.candidate
    while True:
        state = runner.tick(cid)
        if state in S.TERMINAL_CANDIDATE_STATES:
            print(f"candidate {cid} finished in state {state}")
            _print_candidate(st, cid)
            return 0 if state == S.DONE else 2
        if args.once or args.dry_run:
            print(f"candidate {cid} is {state}")
            return 0
        time.sleep(args.poll)


def recipe_catalog() -> list[dict]:
    """Every recipe as the panel and a person should see it, including the ones that fail.

    A recipe that does not validate is listed with its errors rather than dropped: a
    catalog that silently shrinks is the failure that would go unnoticed longest.
    """
    out = [{"id": problem.split(":", 1)[0], "error": problem}
           for problem in recipes._index()[1] if "filename must be" in problem]
    for rid in recipes.available():
        try:
            r = recipes.load(rid)
        except recipes.RecipeError as exc:
            out.append({"id": rid, "error": str(exc)})
            continue
        steps = r["steps"]
        out.append({
            "id": r["id"], "version": str(r["version"]), "source": r["source"],
            "author": r["author"], "description": r.get("description"), "match": r["match"],
            # Reachable by automatic selection at all: some list in `match` is non-empty
            # (format v1 rule 8). Whether it matches a given order is `omakase match`.
            "auto_selectable": any(r["match"].get(k) for k in match.STRING_LISTS),
            "step_count": len(steps),
            "chain": [{"seq": s["seq"], "app_name": s["app_name"],
                       "depends_on_seq": s["depends_on_seq"]} for s in steps],
            "derives_from_species": recipes.FROM_SPECIES in json.dumps(steps),
            "constraints": len(r["constraints"]),
            "gated_steps": [s["app_name"] for s in steps if "when" in s],
        })
    return out


def cmd_match(args, st: S.Store) -> int:
    """Which recipes accept this order, and why the others do not. Writes nothing."""
    event = json.load(Path(args.event).open(encoding="utf-8"))
    P.check_env(event.get("env"), args.prof, f"event {args.event}")
    order = event.get("order") or {}
    dataset = None
    if not args.order_only:
        dataset_id, found_by = _resolve_dataset(args, order)
        dataset = SushiClient(args.base_url, token(args.prof)).dataset(dataset_id)
        print(f"input: {found_by}")
    results = recipes.explain(order, dataset)
    for r in sorted(results, key=lambda r: (not r["matches"], r["recipe"])):
        print(match.describe(r))
    hits = [r["recipe"] for r in results if r["matches"]]
    print(f"\n{len(hits)} of {len(results)} recipes match"
          + (" -> ingest would select it" if len(hits) == 1 else
             " -> ingest would abstain" if hits else " -> ingest would decline"))
    return 0


def cmd_recipes(args, st: S.Store) -> int:
    catalog = recipe_catalog()
    if args.json:
        print(json.dumps({"recipes": catalog, "catalog_dir": str(recipes.catalog_dir() or ""),
                          "fixture_dir": str(recipes.FIXTURE_DIR)}, indent=2))
        return 0
    print(f"fixtures: {recipes.FIXTURE_DIR}\ncatalog:  {recipes.catalog_dir() or '(none)'}\n")
    for r in catalog:
        if "error" in r:
            print(f"INVALID {r['id']}: {r['error']}\n")
            continue
        seqs = {c["seq"]: c for c in r["chain"]}
        parts = [f"{c['app_name']}" + (f"<-{seqs[c['depends_on_seq']]['app_name']}"
                                       if c["depends_on_seq"] else "") for c in r["chain"]]
        extra = [f"{r['constraints']} constraints"] if r["constraints"] else []
        extra += [f"when on {', '.join(r['gated_steps'])}"] if r["gated_steps"] else []
        print(f"{r['source']:<8} {r['id']}@{r['version']}  {r['step_count']} steps: "
              + ", ".join(parts) + (f"  [{'; '.join(extra)}]" if extra else ""))
    return 0


def cmd_gate(args, st: S.Store) -> int:
    """Phase 2. Has OMAKASE earned the right to have a model in the loop yet?"""
    result = gate.score(st.verdicts(), baseline=args.baseline)
    print(gate.describe(result))
    return {gate.PASS: 0, gate.NOT_YET: 1, gate.FAIL: 2}[result["status"]]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--profile", choices=sorted(P.PROFILES), default=None,
                    help=f"B-Fabric instance + backend pair (default $OMAKASE_PROFILE, else "
                         f"{P.DEFAULT}); decides the store, the backend and the token")
    ap.add_argument("--store", type=Path, default=None,
                    help="default ~/.omakase/<profile>/omakase.sqlite3. An explicit path is "
                         "for scratch runs; it is not checked against the profile")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("ingest", help="turn an order event into a proposed candidate")
    p.add_argument("--event", required=True, help="a JSON file from omakase_order_watch")
    p.add_argument("--dataset", type=int, default=None,
                   help="the SUSHI input dataset id. Optional since 2026-09-11: when it is "
                        "left out, the order is resolved to the one parentless dataset in "
                        "its project carrying that order id, and refuses on 0 or many")
    p.add_argument("--recipe", default=None)
    p.add_argument("--history", type=Path, default=DEFAULT_HISTORY,
                   help="the history audit TSV, for counted evidence")
    p.add_argument("--control-every", type=int, default=0,
                   help="put every Nth order id in the control arm (0 = off)")
    p.add_argument("--base-url", default=None,
                   help="the profile's backend; any other value is refused. Only contacted "
                        "to find the dataset or derive a value from it, such as refBuild")
    p.set_defaults(fn=cmd_ingest)

    p = sub.add_parser("show")
    p.add_argument("--candidate", type=int)
    p.add_argument("--state")
    p.set_defaults(fn=cmd_show)

    p = sub.add_parser("approve", help="accept the proposal unchanged (verdict ACCEPTED)")
    p.add_argument("--candidate", type=int, required=True)
    p.add_argument("--actor", required=True)
    p.add_argument("--reason")
    p.set_defaults(fn=cmd_approve)

    p = sub.add_parser("confirm", help="a named person confirms open checklist items")
    p.add_argument("--candidate", type=int, required=True)
    p.add_argument("--item", type=int, action="append", default=[],
                   help="checklist index to confirm (repeatable)")
    p.add_argument("--all", action="store_true", help="every open item")
    p.add_argument("--actor", required=True)
    p.add_argument("--note")
    p.set_defaults(fn=cmd_confirm)

    p = sub.add_parser("revise", help="edit the chain, then approve (verdict EDITED)")
    p.add_argument("--candidate", type=int, required=True)
    p.add_argument("--actor", required=True)
    p.add_argument("--steps", required=True,
                   help="YAML holding the corrected steps, or a mapping with 'steps'")
    p.add_argument("--reason")
    p.set_defaults(fn=cmd_revise)

    p = sub.add_parser("reject", help="refuse the proposal (verdict REJECTED)")
    p.add_argument("--candidate", type=int, required=True)
    p.add_argument("--actor", required=True)
    p.add_argument("--reason")
    p.set_defaults(fn=cmd_reject)

    p = sub.add_parser("labels", help="what the feedback loop has accumulated")
    p.set_defaults(fn=cmd_labels)

    p = sub.add_parser("gate", help="the pre-registered phase-2 gate; rc 0 = PASS")
    p.add_argument("--baseline", type=float, default=gate.BASELINE_WEIGHTED,
                   help="override only with a reason; the default was pre-registered")
    p.set_defaults(fn=cmd_gate)

    p = sub.add_parser("run", help="drive the chain, one step at a time")
    p.add_argument("--candidate", type=int, required=True)
    p.add_argument("--base-url", default=None, help="the profile's backend; others refused")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--once", action="store_true", help="one tick, then exit")
    p.add_argument("--poll", type=int, default=60)
    p.add_argument("--max-retries", type=int, default=1)
    p.set_defaults(fn=cmd_run)

    p = sub.add_parser("match", help="evaluate every recipe's match against an order event")
    p.add_argument("--event", required=True)
    p.add_argument("--dataset", type=int, default=None, help="skip order -> dataset resolution")
    p.add_argument("--order-only", action="store_true",
                   help="no dataset at all: the species rules report 'needs the dataset'")
    p.add_argument("--base-url", default=None, help="the profile's backend; others refused")
    p.set_defaults(fn=cmd_match)

    p = sub.add_parser("recipes", help="list the fixtures and the catalog, invalid ones included")
    p.add_argument("--json", action="store_true", help="machine-readable, for the panel")
    p.set_defaults(fn=cmd_recipes)

    args = ap.parse_args()
    args.prof = P.get(args.profile)
    if getattr(args, "base_url", None) is None:
        args.base_url = args.prof.backend
    elif args.base_url.rstrip("/") != args.prof.backend:
        print(f"refused: --base-url {args.base_url} is not profile {args.prof.name!r}'s "
              f"backend ({args.prof.backend}); pass --profile instead", file=sys.stderr)
        return 2
    st = S.Store(args.store or args.prof.store_path)
    # Tell a person when one is needed (PROPOSED, WAITING) or the chain ends (HALTED, DONE).
    # Outbox only unless OMAKASE_NOTIFY_TO is set; see notify.py.
    st.listeners.append(notify.Notifier(st, args.prof.name, log=lambda m: print(m, file=sys.stderr)))
    try:
        return args.fn(args, st)
    except (input_dataset.InputDatasetError, reference.ReferenceError,
            recipes.RecipeError, P.EnvMismatch) as exc:
        # These are refusals, not crashes. An order whose data is not registered yet, a
        # dataset with no Species, a recipe that matches nothing -- all of them are the
        # system declining to proceed on purpose, and a traceback would read as a defect
        # to anyone watching. rc 3 so a caller can tell "declined" from "failed" (2).
        print(f"\nDECLINED: {exc}", file=sys.stderr)
        return 3
    finally:
        st.close()


if __name__ == "__main__":
    sys.exit(main())
