#!/usr/bin/env python3
"""What ingest asks the backend before a proposal exists. rc 0 = every refusal still refuses.

    python3 omakase_core/test_ingest_checks.py

No network: SushiClient is replaced by a fake that knows three apps and two datasets.
"""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

from omakase_core import constraints as K, input_dataset, omakase as O, recipes  # noqa: E402

cases = 0


def case(name):
    global cases
    cases += 1
    print(f"  ok  {name}")


class FakeSushi:
    DEFAULTS = {"CellRangerApp": {"cores": "8", "refBuild": ""},
                "ScSeuratApp": {"CyteTypeR": "false"},
                "CellRangerMultiApp": {"cores": "8"}}
    DATASETS = {819: {"id": 819, "project_number": 35611}, 134: {"id": 134, "project_number": 34606}}

    def __init__(self, *a, **k):
        pass

    def app_defaults(self, app):
        return self.DEFAULTS.get(app)

    def project_datasets(self, project):
        if project != 35611:
            raise O.SushiError("403 Project not accessible")
        return [{"id": 9, "name": "ventricles_100k", "parent_id": None, "samples_count": 2},
                {"id": 873, "name": "omakase_c1_s1_FastqcApp", "parent_id": 9, "samples_count": 2},
                {"id": 825, "name": "tiny_tar", "parent_id": None, "samples_count": 1}]

    def dataset(self, ds):
        if ds not in self.DATASETS:
            raise O.SushiError(f"404 dataset {ds}")
        return {"dataset": self.DATASETS[ds]}


O.SushiClient = FakeSushi
O.token = lambda prof=None: "fake"
args = SimpleNamespace(base_url="http://fake", prof=None, dataset=None)


def recipe(raw_steps, raw_constraints=()):
    items = K.compile_items(list(raw_constraints), raw_steps)
    return {"id": "t", "version": "1", "items": items}


def steps(*spec):
    return [{"seq": i + 1, "app_name": app, "parameters": params, "retry_parameters": None}
            for i, (app, params) in enumerate(spec)]


# --- an app the backend does not serve, on an unconditional step: declined, nothing proposed
raw = [{"app": "CellRangerApp"}, {"app": "ScSeuratCombineApp", "after": []}]
try:
    O._assess(recipe(raw), steps(("CellRangerApp", {}), ("ScSeuratCombineApp", {})), args)
    raise AssertionError("a missing app was proposed")
except recipes.RecipeError as exc:
    assert "ScSeuratCombineApp" in str(exc) and "Nothing was proposed" in str(exc)
case("an unconditional step whose app the backend does not serve DECLINES the recipe")

# --- the same app behind a `when`: proposed, and the gate says it can only be skipped
raw = [{"app": "CellRangerApp"}, {"app": "ScSeuratCombineApp", "after": [], "when": "n >= 2"}]
out = O._assess(recipe(raw), steps(("CellRangerApp", {}), ("ScSeuratCombineApp", {})), args)
gate = next(i for i in out if i["idx"] == K.WHEN_BASE + 2)
assert gate["status"] == K.PENDING and "can only be skipped" in gate["detail"]
case("behind a `when`, a missing app is proposed with a gate that says: skip only")

# --- a parameter the app does not declare: a hold before that step
raw = [{"app": "CellRangerMultiApp"}]
out = O._assess(recipe(raw), steps(("CellRangerMultiApp", {"cores": "8", "chemistry": "SC5P-R2"})),
                args)
hold = next(i for i in out if i["idx"] == K.PARAMS_BASE + 1)
assert (hold["kind"], hold["severity"], hold["at_step_seq"], hold["status"]) == \
       (K.MANUAL, "hold", 1, K.PENDING) and "chemistry" in hold["assert"]
assert not any(i["idx"] == K.PARAMS_BASE + 1 for i in
               O._assess(recipe(raw), steps(("CellRangerMultiApp", {"cores": "8"})), args))
case("an undeclared parameter (chemistry on CellRangerMulti) becomes a hold; a clean step gets none")

# --- a named dataset must be in the order's project
order = {"id": 35755, "project": {"id": 35611}}
args.dataset = 819
ds, how = O._resolve_dataset(args, order)
assert ds == 819 and "project 35611" in how
args.dataset = 134
try:
    O._resolve_dataset(args, order)
    raise AssertionError("a dataset from another project was accepted")
except input_dataset.InputDatasetError as exc:
    assert "project 34606" in str(exc) and "35611" in str(exc)
args.dataset = 999
try:
    O._resolve_dataset(args, order)
    raise AssertionError("an unreadable dataset was accepted")
except input_dataset.InputDatasetError as exc:
    assert "cannot be read with this key" in str(exc)
case("a named dataset in the order's project is used; another project's, or an unreadable one, is refused")


# --- `omakase datasets`: the choices for --dataset, raw ones first
import io, json  # noqa: E402,E401
from contextlib import redirect_stdout  # noqa: E402
out = io.StringIO()
with redirect_stdout(out):
    rc = O.cmd_datasets(SimpleNamespace(base_url="x", prof=None, project=35611, all=False, json=True), None)
d = json.loads(out.getvalue())
assert rc == 0 and [x["id"] for x in d["datasets"]] == [825, 9] and all(x["raw"] for x in d["datasets"])
out = io.StringIO()
with redirect_stdout(out):
    O.cmd_datasets(SimpleNamespace(base_url="x", prof=None, project=35611, all=True, json=True), None)
assert [x["id"] for x in json.loads(out.getvalue())["datasets"]] == [825, 9, 873]
case("datasets lists raw datasets first (newest first); --all adds the derived ones")
print(f"{cases} cases, all pass")
