#!/usr/bin/env python3
"""Recipe format v1: loading, validation, compilation, template expansion. rc 0 = all pass.

    python3 omakase_core/test_recipes.py

Self-contained: a synthetic catalog (recipes + a per-assay reference policy + a fake
reference root) is written to a temporary directory and selected with OMAKASE_CATALOG_DIR.
The real catalog — the local clone of Paul's MR — is checked only if it is present, and
nothing from it is copied into this file.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))
REAL_CATALOG = os.environ.get("OMAKASE_CATALOG_DIR")  # remembered before the override

TMP = Path(tempfile.mkdtemp(prefix="omakase_recipes_test_"))
CAT = TMP / "catalog"
(CAT / "recipes").mkdir(parents=True)
REF_ROOT = TMP / "reference"
BUILD = "Mus_musculus/GENCODE/GRCm39/Annotation/Release_TEST"
(REF_ROOT / BUILD).mkdir(parents=True)
(CAT / "references.yaml").write_text(yaml.safe_dump({
    "version": 1, "species_aliases": {"Mus musculus": "Mus_musculus"},
    "assays": {"demo": {"used_by": ["demo_assay"], "Mus_musculus": {"refBuild": BUILD}},
               "imaging": {"used_by": ["demo_noref"], "no_reference": True}},
    "reference_root": str(REF_ROOT)}))
os.environ["OMAKASE_CATALOG_DIR"] = str(CAT)

from omakase_core import recipes as R, reference  # noqa: E402

cases = 0


def case(name):
    global cases
    cases += 1
    print(f"  ok  {name}")


def recipe(**over):
    body = {"schema_version": 1, "id": "demo_assay", "version": 1, "author": "test",
            "match": {"sequencing_application": ["Demo"]},
            "steps": [{"app": "STARApp", "params": {"ram": "30",
                                                    "refBuild": "{{ reference_for(species) }}",
                                                    "transcriptTypes": ["protein_coding", "rRNA"]},
                       "retry_params": {"ram": "60"}},
                      {"app": "FeatureCountsApp", "params": {"refBuild": "{{ same_as_previous }}"}}],
            "autostart": False, "autostart_blocked_by": "test"}
    body.update(over)
    return body


def write(body, name=None):
    for old in (CAT / "recipes").glob("*.yaml"):
        old.unlink()
    path = CAT / "recipes" / (name or f"{body['id']}_v{body['version']}.yaml")
    path.write_text(yaml.safe_dump(body, sort_keys=False))
    return path


def invalid(body, needle, name=None):
    write(body, name)
    try:
        R.load(body.get("id", "demo_assay"))
    except R.RecipeError as exc:
        assert needle in str(exc), (needle, str(exc))
        return True
    return False


MOUSE = {"samples": [{"Species": "Mus musculus"}, {"Species": "Mus musculus"}]}

# --- the fixtures committed with the engine
for rid in ("acceptance_halt_fixture", "fastqc_only", "flash_then_fastqc",
            "rnaseq_meeting_shape", "star_then_featurecounts"):
    assert R.load(rid)["source"] == "fixture"
case("all 5 engine fixtures load as format v1")
shape = R.load("rnaseq_meeting_shape")["steps"]
assert [s["depends_on_seq"] for s in shape] == [None, None, None, 3]
case("rnaseq_meeting_shape keeps its parallelism: 3 independent steps, FeatureCounts after STAR")
star = R.load("star_then_featurecounts")["steps"]
assert star[0]["retry_parameters"] == {"cores": 8, "ram": 60, "scratch": 200,
                                       "refBuild": R.FROM_SPECIES, "paired": True,
                                       "strandMode": "both"}
assert [s["depends_on_seq"] for s in star] == [None, 1]
case("retry_params overlays to the same full set the pre-v1 file spelled out")

# --- compilation of a synthetic catalog recipe
write(recipe())
r = R.load("demo_assay")
assert r["source"] == "catalog"
s1, s2 = r["steps"]
assert s1["parameters"]["transcriptTypes"] == "protein_coding,rRNA"
case("a YAML list is a multi-select, comma-joined for SUSHI")
assert s1["parameters"]["refBuild"] == R.FROM_SPECIES and s2["parameters"]["refBuild"] == R.SAME_AS_PREVIOUS
assert s1["retry_parameters"]["refBuild"] == R.FROM_SPECIES
case("templates compile to sentinels, retry values included")

# --- expansion
out, notes = R.resolve_parameters(r["steps"], MOUSE, "demo_assay")
assert out[0]["parameters"]["refBuild"] == BUILD and out[1]["parameters"]["refBuild"] == BUILD
assert out[0]["retry_parameters"]["refBuild"] == BUILD
assert "references.yaml:demo/Mus_musculus" in notes[0]
case("reference_for(species) uses the per-assay family; same_as_previous copies it")
for species, needle in ((["Rattus norvegicus"], "not in references.yaml's species_aliases"),
                        ([], "no usable Species"),
                        (["Mus musculus", "Homo sapiens"], "carries 2 species")):
    ds = {"samples": [{"Species": x} for x in species]}
    try:
        R.resolve_parameters(r["steps"], ds, "demo_assay")
        raise AssertionError(f"{species} was not refused")
    except reference.ReferenceError as exc:
        assert needle in str(exc), (needle, str(exc))
case("per-assay lookup refuses an unaliased species, no species, and two species")
(REF_ROOT / BUILD).rmdir()
try:
    R.resolve_parameters(r["steps"], MOUSE, "demo_assay")
    raise AssertionError("missing build was not refused")
except reference.ReferenceError as exc:
    assert "not on disk" in str(exc)
(REF_ROOT / BUILD).mkdir(parents=True)
case("a build the policy names but the disk lacks is refused")
write(recipe(id="demo_noref"))
try:
    R.resolve_parameters(R.load("demo_noref")["steps"], MOUSE, "demo_noref")
    raise AssertionError("no_reference family was not refused")
except reference.ReferenceError as exc:
    assert "uses no reference genome" in str(exc)
case("a no_reference family refuses reference_for")
no_up = recipe(steps=[{"app": "STARApp", "params": {"ram": "30"}},
                      {"app": "ScSeuratApp", "params": {"refBuild": "{{ same_as_previous }}"}}])
write(no_up)
try:
    R.resolve_parameters(R.load("demo_assay")["steps"], None, "demo_assay")
    raise AssertionError("same_as_previous without an upstream value was not refused")
except R.RecipeError as exc:
    assert "upstream step does not set it" in str(exc)
case("same_as_previous refuses when the upstream step does not set the key")

# --- validation: every refusal
S = recipe()["steps"]
negatives = [
    (recipe(steps=[{**S[0], "id": "a", "after": ["b"]}, {**S[1], "id": "b"}]), "not an EARLIER"),
    (recipe(steps=[{**S[0], "id": "a"}, {**S[1], "id": "b"},
                   {"app": "CountQCApp", "after": ["a", "b"]}]), "this engine allows one"),
    (recipe(steps=[{"app": "STARApp", "params": {"refBuild": "{{ species == 'Mus musculus' }}"}}]),
     "unknown template"),
    (recipe(steps=[{"app": "STARApp", "params": {"x": "pre-{{ same_as_previous }}"}}]),
     "must be the whole value"),
    (recipe(steps=[{"app": "STARApp", "params": {"refBuild": "FROM_SPECIES"}}]),
     "not the internal sentinel"),
    (recipe(steps=[{"app": "STARApp", "params": {"refBuild": "{{ same_as_previous }}"}}]),
     "needs exactly one upstream"),
    (recipe(steps=[{"seq": 1, "app": "STARApp"}]), "unknown key 'seq'"),
    (recipe(schema_version=2), "reads v1 only"),
    (recipe(match={"sequencing_application": "Demo"}), "must be a list of strings"),
    (recipe(autostart=False, autostart_blocked_by=None), "needs autostart_blocked_by"),
    (recipe(steps=[{**S[0], "id": "x"}, {**S[1], "id": "x"}]), "duplicate step id"),
    (recipe(constraints=[{"assert": "a", "reason": "r",
                          "check": {"step": "STARApp", "param": "ram", "equals": "30",
                                    "one_of": ["30"]}}]), "exactly one operator"),
    (recipe(constraints=[{"assert": "a", "reason": "r",
                          "check": {"step": "CellRanger", "param": "ram", "equals": "30"}}]),
     "names 0 steps"),
    (recipe(constraints=[{"assert": "a", "reason": "r", "check": "python: x == 1"}]),
     "check must be 'manual'"),
    (recipe(constraints=[{"assert": "a", "reason": "r",
                          "check": {"step": "STARApp", "param": "v", "version_at_least": ">=10"}}]),
     "dotted version"),
    (recipe(constraints=[{"assert": "a", "reason": "r", "at": {"before_step": "Nope"}}]),
     "names 0 steps"),
]
for body, needle in negatives:
    assert invalid(body, needle), (needle, body)
case(f"{len(negatives)} malformed recipes are each refused with the specific reason")
assert invalid(recipe(version="v1"), "version must be an integer", name="demo_assay_v1.yaml")
case("a non-integer version is refused")
assert invalid(recipe(), "do not match the filename", name="demo_assay_v7.yaml")
case("a filename that disagrees with id/version is refused")
write(recipe(id="fastqc_only"))
try:
    R.load("fastqc_only")
    raise AssertionError("an id in both places was not refused")
except R.RecipeError as exc:
    assert "exists in both" in str(exc)
case("the same id in the fixtures and the catalog is refused, never merged")
try:
    R.select({"id": 1})
    raise AssertionError("unnamed selection did not refuse")
except R.RecipeError as exc:
    assert "name one with --recipe" in str(exc)
case("select() without a name refuses until match evaluation exists")


# --- the CLI
def cli(*argv):
    r = subprocess.run([sys.executable, "-m", "omakase_core.omakase", *argv], cwd=SCRIPTS,
                       env=dict(os.environ, OMAKASE_ROOT=str(TMP / "home")),
                       capture_output=True, text=True, timeout=120)
    return r.returncode, r.stdout + r.stderr


event = TMP / "event.json"
event.write_text(json.dumps({"env": "TEST", "order": {"id": 35755, "project": {"id": 35611}}}))
write(recipe(constraints=[{"assert": "ram is 30", "reason": "r"}]))
rc, out = cli("ingest", "--event", str(event), "--dataset", "9", "--recipe", "demo_assay")
assert rc == 3 and "does not evaluate yet" in out, (rc, out)
case("ingest DECLINES a recipe with constraints instead of ignoring them (rc 3)")
write(recipe(steps=[S[0], {**S[1], "when": "n_samples >= 2"}]))
rc, out = cli("ingest", "--event", str(event), "--dataset", "9", "--recipe", "demo_assay")
assert rc == 3 and "`when` on FeatureCountsApp" in out, (rc, out)
case("ingest DECLINES a recipe with a `when` it cannot evaluate (rc 3)")
write(recipe(version="broken"), name="demo_assay_v1.yaml")
rc, out = cli("recipes", "--json")
listed = {r["id"]: r for r in json.loads(out)["recipes"]}
assert rc == 0 and "error" in listed["demo_assay"] and "error" not in listed["fastqc_only"]
case("`recipes --json` lists an invalid recipe with its error instead of dropping it")
write(recipe(), name="demo_assay.yaml")
rc, out = cli("recipes", "--json")
assert rc == 0 and any("filename must be" in r.get("error", "") for r in json.loads(out)["recipes"]), out
case("a file that breaks the naming rule is listed as an error, not silently skipped")

# --- the real catalog, only if its clone is here
real = Path(REAL_CATALOG) if REAL_CATALOG else R.DEFAULT_CATALOG
if (real / "recipes").is_dir():
    os.environ["OMAKASE_CATALOG_DIR"] = str(real)
    ids = [p.name.rsplit("_v", 1)[0] for p in sorted((real / "recipes").glob("*_v*.yaml"))]
    loaded = [R.load(i) for i in ids]
    assert all(x["source"] == "catalog" for x in loaded)
    case(f"the real catalog at {real} loads unedited: {len(loaded)} recipes")
else:
    print(f"  --  real catalog not present at {real}; skipped")

print(f"{cases} cases, all pass")
