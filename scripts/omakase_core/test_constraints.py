#!/usr/bin/env python3
"""Constraints: the closed check language, effective parameters, the checklist gates.
rc 0 = every rule and refusal holds.

    python3 omakase_core/test_constraints.py

No network: app defaults are given as dictionaries, the runner uses test_runner's fake
backend. The worked example is the catalog's own data-egress rule (AzimuthPanHuman below
CellRanger 10.1.0) and the includeIntrons default measured on 083.
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

from omakase_core import constraints as K, runner as R, store as S  # noqa: E402
from omakase_core.test_runner import FakeClient  # noqa: E402

cases = 0


def case(name):
    global cases
    cases += 1
    print(f"  ok  {name}")


RAW_STEPS = [{"app": "CellRangerApp"}, {"app": "ScSeuratApp"}, {"id": "combine", "app": "ScSeuratCombineApp",
                                                              "when": "n_samples >= 2"}]
AZIMUTH = {"if": {"step": "ScSeurat", "param": "AzimuthPanHuman", "equals": True},
           "then": {"step": "CellRanger", "param": "CellRangerVersion", "version_at_least": "10.1.0"}}
RAW = [
    {"assert": "AzimuthPanHuman only on >= 10.1.0", "reason": "egress", "check": AZIMUTH},
    {"assert": "CyteTypeR is false", "reason": "egress", "severity": "refuse",
     "check": {"step": "ScSeurat", "param": "CyteTypeR", "equals": False}},
    {"assert": "the FastqScreen species agrees", "reason": "r", "at": {"before_step": "ScSeurat"}},
    {"assert": "partition is employee", "reason": "r", "severity": "hold",
     "check": {"step": "CellRanger", "param": "partition", "equals": "employee"}},
]
DEFAULTS = {"CellRangerApp": {"CellRangerVersion": "Aligner/CellRanger/10.1.0", "partition": "user",
                              "includeIntrons": True},
            "ScSeuratApp": {"AzimuthPanHuman": False, "CyteTypeR": False},
            "ScSeuratCombineApp": {}}


def steps(cr=None, seu=None, cr_retry=None):
    return [{"seq": 1, "app_name": "CellRangerApp", "parameters": cr or {},
             "retry_parameters": cr_retry},
            {"seq": 2, "app_name": "ScSeuratApp", "parameters": seu or {}, "retry_parameters": None},
            {"seq": 3, "app_name": "ScSeuratCombineApp", "parameters": {}, "retry_parameters": None}]


items = K.compile_items(RAW, RAW_STEPS)
by = {i["idx"]: i for i in items}
assert [by[0]["kind"], by[2]["kind"], by[1003]["kind"]] == [K.MACHINE, K.MANUAL, K.WHEN]
assert by[0]["check"]["then"]["step"] == 1 and by[2]["at_step_seq"] == 2 and by[1003]["at_step_seq"] == 3
case("rules compile to items; step references resolve to positions; `when` becomes a gate")

# --- effective parameters: defaults matter
a = {i["idx"]: i for i in K.assess(items, steps(), DEFAULTS)}
assert a[0]["status"] == K.PASS and "condition does not apply" in a[0]["detail"]
assert a[1]["status"] == K.PASS
case("recipe silent, defaults safe: both egress rules PASS on the effective parameters")
a = {i["idx"]: i for i in K.assess(items, steps(seu={"AzimuthPanHuman": True},
                                                 cr={"CellRangerVersion": "Aligner/CellRanger/10.0.0"}),
                                   DEFAULTS)}
assert a[0]["status"] == K.FAIL and "10.0.0" in a[0]["detail"]
assert [i["idx"] for i in K.refusals(list(a.values()))] == [0]
case("AzimuthPanHuman on with CellRanger 10.0.0 FAILS and is a refusal")
danger = dict(DEFAULTS, ScSeuratApp={"AzimuthPanHuman": False, "CyteTypeR": True})
a = {i["idx"]: i for i in K.assess(items, steps(), danger)}
assert a[1]["status"] == K.FAIL
case("a dangerous DEFAULT is caught although the recipe never mentions the key")
a = {i["idx"]: i for i in K.assess(items, steps(cr={"CellRangerVersion": "Aligner/CellRanger/10.1.0"},
                                                 cr_retry={"CellRangerVersion": "Aligner/CellRanger/9.0.0"},
                                                 seu={"AzimuthPanHuman": True}), DEFAULTS)}
assert a[0]["status"] == K.FAIL and "RETRY" in a[0]["detail"]
case("a retry that would break a rule fails the rule")
a = {i["idx"]: i for i in K.assess(items, steps(), dict(DEFAULTS, CellRangerApp=None))}
assert a[3]["status"] == K.FAIL and "not known to the backend" in a[3]["detail"]
case("an app the backend does not know fails its rules (fail closed)")
bad = [{"assert": "x", "reason": "r", "check": {"step": "CellRanger", "param": "noSuchKey", "equals": "1"}}]
a = K.assess(K.compile_items(bad, RAW_STEPS), steps(), DEFAULTS)
assert a[0]["status"] == K.FAIL and "neither an app default nor set" in a[0]["detail"]
case("a rule about a key that is neither a default nor in the recipe fails")

# --- the operators
E = lambda expr, params: K.evaluate(expr, {1: params}, {1: "X"})[0]
assert E({"step": 1, "param": "p", "one_of": ["a", "b"]}, {"p": "b"})
assert E({"step": 1, "param": "p", "contains": "--disable"}, {"p": "--x --disable-cell-annotation"})
assert E({"step": 1, "param": "p", "matches": r"[A-D]-[A-H]\d\d"}, {"p": "B-C07"})
assert not E({"step": 1, "param": "p", "matches": r"[A-D]"}, {"p": "B-C07"})     # fullmatch
assert E({"step": 1, "param": "p", "equals": True}, {"p": "true"})
assert E({"step": 1, "param": "v", "version_at_least": "10.0"}, {"v": "Aligner/CellRanger/10.0.0"})
assert not E({"step": 1, "param": "v", "version_at_least": "10.1.0"}, {"v": "Aligner/CellRanger/10.0.0"})
assert not E({"step": 1, "param": "v", "version_at_least": "1"}, {"v": "latest"})
assert E({"any": [{"step": 1, "param": "p", "equals": "x"}, {"not": {"step": 1, "param": "p", "equals": "y"}}]}, {"p": "z"})
assert not E({"all": [{"step": 1, "param": "p", "equals": "z"}, {"step": 1, "param": "q", "equals": "1"}]}, {"p": "z"})
case("equals/one_of/contains/matches(fullmatch)/version_at_least/all/any/not, unparsable version fails")

# --- store + gates
tmp = Path(tempfile.mkdtemp(prefix="omakase_constraints_test_"))
st = S.Store(tmp / "s.sqlite3")
cid, _ = st.upsert_candidate(42, 9, "demo", "1", project_number=35611)
st.set_steps(cid, [{"seq": 1, "app_name": "FastqcApp", "depends_on_seq": None, "parameters": {}},
                   {"seq": 2, "app_name": "FastqcApp", "depends_on_seq": None, "parameters": {}},
                   {"seq": 3, "app_name": "FastqcApp", "depends_on_seq": 2, "parameters": {}}])
checklist = K.assess(K.compile_items(
    [{"assert": "before start", "reason": "r"},
     {"assert": "before step 3", "reason": "r", "at": {"before_step": "s3"}}],
    [{"id": "s1", "app": "FastqcApp"}, {"id": "s2", "app": "FastqcApp"},
     {"id": "s3", "app": "FastqcApp", "after": ["s2"]}]), [], {})
st.set_checklist(cid, checklist)
assert [i["idx"] for i in K.open_items(st.checklist(cid), None)] == [0]
st.set_state(cid, S.APPROVED, "test", "forced, to test the runner's own lock")
run = R.ChainRunner(st, FakeClient({}, applicable={"Fastqc"}), log=lambda *_: None)
assert run.tick(cid) == S.APPROVED and not run.client.submits
case("the runner will not start a chain with a before-start item open (second lock)")
st.confirm_item(cid, 0, "masaomi", "checked")
for _ in range(6):
    state = run.tick(cid)
assert state == S.RUNNING and len(run.client.submits) == 2
case("before step 3 open: steps 1 and 2 run, step 3 waits, the chain is NOT halted")
st.confirm_item(cid, 1, "masaomi")
for _ in range(6):
    state = run.tick(cid)
assert state == S.DONE and len(run.client.submits) == 3
assert all(i["confirmed_by"] == "masaomi" for i in st.checklist(cid))
case("confirming the gate releases step 3; every confirmation names who")
try:
    st.confirm_item(cid, 0, "someone")
    raise AssertionError("re-confirming a confirmed item was accepted")
except ValueError:
    pass
case("an item cannot be confirmed twice")

print(f"{cases} cases, all pass")
