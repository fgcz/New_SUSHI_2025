"""A recipe's `constraints` and `when`, turned into a checklist the chain cannot skip.

Every rule becomes one item on the candidate:

    MACHINE  it has a `check` expression -> evaluated here, before the proposal is stored,
             on the EFFECTIVE parameters of both the first attempt and the retry
    MANUAL   `check: manual` or no check  -> PENDING until a named person confirms it
    WHEN     a step's `when` (the engine does not evaluate conditions) -> PENDING, gating
             that step; confirm it holds, or revise the chain to drop the step

and carries `at`: before the chain's first submission (at_step_seq NULL), or before one
step. What happens next is fixed in code:

    MACHINE fails, severity refuse  -> the recipe is DECLINED for this order; no candidate
    MACHINE fails, severity hold    -> FAIL, and like PENDING it needs a person to confirm
    anything unconfirmed before_submit -> `approve` is refused
    anything unconfirmed before step N -> the runner submits everything else and waits at N

Effective parameters are the app's defaults as the backend resolves them, overlaid by the
step's parameters, stringified exactly as submitted (booleans `true`/`false`). A rule about a
key that is neither a default nor in the recipe FAILS; so does a step whose app the backend
does not know. Nothing is guessed, nothing is eval'd: the check language is closed (see
recipes.py) and interpreted here.
"""
from __future__ import annotations

import json
import re
from typing import Any

MACHINE, MANUAL, WHEN = "MACHINE", "MANUAL", "WHEN"
PASS, FAIL, PENDING, CONFIRMED = "PASS", "FAIL", "PENDING", "CONFIRMED"
WHEN_BASE = 1000                         # item index of step N's `when` gate = 1000 + N


def compile_items(raw_constraints: list[dict], raw_steps: list[dict]) -> list[dict[str, Any]]:
    """Recipe rules -> checklist items with every step reference resolved to a seq."""
    from .recipes import step_index
    seq = lambda ref: step_index(ref, raw_steps)[0] + 1            # validated: exactly one
    items = []
    for i, con in enumerate(raw_constraints or []):
        chk = con.get("check", "manual")
        at = con.get("at", "before_submit")
        items.append({
            "idx": i,
            "kind": MANUAL if chk == "manual" else MACHINE,
            "severity": con.get("severity", "refuse"),
            "at_step_seq": None if at == "before_submit" else seq(at["before_step"]),
            "assert": con["assert"], "reason": con.get("reason"),
            "check": None if chk == "manual" else _resolve_refs(chk, seq),
        })
    for n, step in enumerate(raw_steps, start=1):
        if "when" in step:
            items.append({
                "idx": WHEN_BASE + n, "kind": WHEN, "severity": "hold", "at_step_seq": n,
                "assert": f"step {n} ({step['app']}) runs only when: {step['when']}",
                "reason": "`when` is not evaluated by the engine: confirm it holds for this "
                          "order, or revise the chain to drop the step",
                "check": None})
    return items


def _resolve_refs(expr: dict, seq) -> dict:
    if "step" in expr:
        return {**expr, "step": seq(expr["step"])}
    out = {}
    for k, v in expr.items():
        out[k] = ([_resolve_refs(x, seq) for x in v] if isinstance(v, list)
                  else _resolve_refs(v, seq) if isinstance(v, dict) else v)
    return out


# ------------------------------------------------------------------------ evaluate


def stringify(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return "" if value is None else str(value)


def effective(defaults: dict | None, params: dict | None) -> dict[str, str] | None:
    if defaults is None:
        return None
    merged = {**defaults, **(params or {})}
    return {k: stringify(v) for k, v in merged.items()}


def _version(text: str) -> tuple[int, ...] | None:
    tail = text.rsplit("/", 1)[-1]
    return tuple(int(x) for x in tail.split(".")) if re.fullmatch(r"\d+(\.\d+)*", tail) else None


def evaluate(expr: dict, params_by_seq: dict[int, dict | None],
             apps: dict[int, str]) -> tuple[bool, str]:
    """(holds, why) for one check expression. Any doubt is a failure."""
    if "all" in expr:
        parts = [evaluate(e, params_by_seq, apps) for e in expr["all"]]
        bad = [w for ok, w in parts if not ok]
        return (not bad, "; ".join(bad) if bad else "all hold")
    if "any" in expr:
        parts = [evaluate(e, params_by_seq, apps) for e in expr["any"]]
        good = [w for ok, w in parts if ok]
        return (bool(good), good[0] if good else "none holds: " + "; ".join(w for _, w in parts))
    if "not" in expr:
        ok, why = evaluate(expr["not"], params_by_seq, apps)
        return (not ok, f"not ({why})")
    if "if" in expr:
        ok, why = evaluate(expr["if"], params_by_seq, apps)
        if not ok:
            return True, f"condition does not apply ({why})"
        ok2, why2 = evaluate(expr["then"], params_by_seq, apps)
        return ok2, f"{why}, so {why2}"
    seq, key = expr["step"], expr["param"]
    params = params_by_seq.get(seq)
    label = f"{apps.get(seq, f'step {seq}')}.{key}"
    if params is None:
        return False, f"{apps.get(seq)} is not known to the backend, so {key} cannot be checked"
    if key not in params:
        return False, f"{label} is neither an app default nor set by the recipe"
    v = params[key]
    op = next(o for o in ("equals", "one_of", "contains", "matches", "version_at_least") if o in expr)
    want = expr[op]
    if op == "equals":
        ok = v == stringify(want)
    elif op == "one_of":
        ok = v in {stringify(w) for w in want}
    elif op == "contains":
        ok = want in v
    elif op == "matches":
        ok = re.fullmatch(want, v) is not None
    else:
        have = _version(v)
        if have is None:
            return False, f"{label} = {v!r} carries no parsable version"
        need = tuple(int(x) for x in want.split("."))
        width = max(len(have), len(need))
        ok = have + (0,) * (width - len(have)) >= need + (0,) * (width - len(need))
    return ok, f"{label} = {v!r} ({op} {json.dumps(want)}: {'holds' if ok else 'fails'})"


def assess(items: list[dict], steps: list[dict], defaults_by_app: dict[str, dict | None]
           ) -> list[dict[str, Any]]:
    """Evaluate every MACHINE item on first-attempt AND retry parameters; others PENDING."""
    apps = {s["seq"]: s["app_name"] for s in steps}
    first = {s["seq"]: effective(defaults_by_app.get(s["app_name"]), s.get("parameters"))
             for s in steps}
    retry = {s["seq"]: effective(defaults_by_app.get(s["app_name"]),
                                 s.get("retry_parameters") or s.get("parameters"))
             for s in steps}
    out = []
    for item in items:
        item = dict(item)
        if item["kind"] != MACHINE:
            item.update(status=PENDING, detail=None)
            out.append(item)
            continue
        if not _refs_present(item["check"], apps):
            item.update(status=FAIL, detail="the chain no longer has the step this rule is about")
            out.append(item)
            continue
        ok1, why1 = evaluate(item["check"], first, apps)
        ok2, why2 = evaluate(item["check"], retry, apps)
        if ok1 and ok2:
            item.update(status=PASS, detail=why1)
        elif not ok1:
            item.update(status=FAIL, detail=why1)
        else:                                  # a retry that breaks a rule must not happen
            item.update(status=FAIL, detail=f"the RETRY would break it: {why2}")
        out.append(item)
    return out


def _refs_present(expr: Any, apps: dict[int, str]) -> bool:
    if isinstance(expr, dict):
        if "step" in expr:
            return expr["step"] in apps
        return all(_refs_present(v, apps) for v in expr.values())
    if isinstance(expr, list):
        return all(_refs_present(v, apps) for v in expr)
    return True


def refusals(assessed: list[dict]) -> list[dict]:
    return [i for i in assessed if i["kind"] == MACHINE and i["status"] == FAIL
            and i["severity"] == "refuse"]


def open_items(checklist: list[dict], at_step_seq: int | None | str = "any") -> list[dict]:
    """Items still waiting for a person, optionally only those gating one point."""
    waiting = [i for i in checklist if i["status"] in (PENDING, FAIL) and not
               (i["kind"] == MACHINE and i["severity"] == "refuse")]
    if at_step_seq == "any":
        return waiting
    return [i for i in waiting if i["at_step_seq"] == at_step_seq]


def describe(item: dict) -> str:
    where = ("before the chain starts" if item["at_step_seq"] is None
             else f"before step {item['at_step_seq']}")
    who = f" by {item['confirmed_by']}" if item.get("confirmed_by") else ""
    tail = f" — {item['detail']}" if item.get("detail") else ""
    return (f"[{item['idx']}] {item['status']:<9} {item['kind'].lower():<7} "
            f"{item['severity']:<6} {where}: {item['assert']}{who}{tail}")
