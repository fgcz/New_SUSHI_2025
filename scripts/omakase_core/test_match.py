#!/usr/bin/env python3
"""`match` evaluation and automatic selection. rc 0 = every rule and refusal holds.

    python3 omakase_core/test_match.py

Self-contained: a synthetic catalog in a temporary OMAKASE_CATALOG_DIR, synthetic orders
and datasets. No network, no B-Fabric.
"""
from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

import yaml

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))
TMP = Path(tempfile.mkdtemp(prefix="omakase_match_test_"))
CAT = TMP / "catalog"
(CAT / "recipes").mkdir(parents=True)
REF = TMP / "reference"
BUILD = "Mus_musculus/GENCODE/GRCm39/Annotation/Release_TEST"
(REF / BUILD).mkdir(parents=True)
(CAT / "references.yaml").write_text(yaml.safe_dump({
    "species_aliases": {"Mus musculus": "Mus_musculus"}, "reference_root": str(REF),
    "assays": {"sc": {"used_by": ["sc_a", "sc_b"], "Mus_musculus": {"refBuild": BUILD}}}}))
os.environ["OMAKASE_CATALOG_DIR"] = str(CAT)

from omakase_core import match as M, recipes as R  # noqa: E402

cases = 0


def case(name):
    global cases
    cases += 1
    print(f"  ok  {name}")


def put(rid, match_block):
    (CAT / "recipes" / f"{rid}_v1.yaml").write_text(yaml.safe_dump({
        "id": rid, "version": 1, "author": "t", "match": match_block,
        "steps": [{"app": "FastqcApp"}], "autostart": False, "autostart_blocked_by": "t"}))


def order(**kw):
    base = {"id": 1, "sequencingapplication": "Single-Cell - BD Rhapsody",
            "instrument": "Illumina NovaSeq X Plus", "countsamples": 4, "numberofsamples": None}
    base.update(kw)
    return base


MOUSE = {"samples": [{"Species": "Mus musculus"}]}

# --- canonical form
C = M.canonical
assert C("Single-Cell - BD Rhapsody") == C("BD Rhapsody")
assert C("Spatial - 10x Genomics - Visium") == C("10x Genomics Visium")
case("a category prefix is folded (the audit's duplicate pairs)")
assert C("Flex Gene Experssion") == C("Flex Gene Expression")
case("the one known misspelling is folded")
assert C("10x 3’ Gene Expression") == C("10x 3' Gene Expression") != C("10x 5' Gene Expression")
case("typographic apostrophes are folded; 3' and 5' stay different")
assert C("SARS-CoV-2 Whole Genome Sequencing") != C("Whole Genome Sequencing")
assert C("Illumina") != C("Illumina NovaSeq X Plus")
case("no containment: SARS-CoV-2 WGS is not WGS, and a vendor is not a model")

# --- evaluate
rec = {"id": "sc_a", "version": 1, "match": {
    "sequencing_application": ["BD Rhapsody"], "instrument": ["Illumina NovaSeq X Plus"],
    "samples": {"min": 1, "max": 8}}}
assert M.evaluate(rec, order())["matches"]
case("every constrained rule passes -> match")
assert not M.evaluate(rec, order(instrument=None))["matches"]
case("an order without a constrained field does not match")
assert not M.evaluate(rec, order(countsamples=12))["matches"]
r = M.evaluate(rec, order(countsamples=0, numberofsamples=None))
assert not r["matches"] and "no sample count" in M.describe(r)
assert M.evaluate(rec, order(countsamples=0, numberofsamples=3))["matches"]
case("samples: out of range fails, unknown fails, the declared count is the fallback")
assert not M.evaluate({"id": "x", "version": 1, "match": {
    "sequencing_application": [], "samples": {"min": 1, "max": 9}}}, order())["matches"]
case("a match with every list empty matches no order, whatever else it says")
sp = {"id": "sc_a", "version": 1, "match": {"sequencing_application": ["BD Rhapsody"],
                                            "species": ["Mus musculus"],
                                            "species_in_reference_catalog": True}}
r = M.evaluate(sp, order())
assert not r["matches"] and r["needs_dataset"] and M.order_level_ok(r)
case("species rules without a dataset: order-level pass, needs_dataset, no match")
assert M.evaluate(sp, order(), MOUSE)["matches"]
assert not M.evaluate(sp, order(), {"samples": [{"Species": "Homo sapiens"}]})["matches"]
assert not M.evaluate(sp, order(), {"samples": [{"Species": "NA"}]})["matches"]
case("species with a dataset: in the list matches; another species or none does not")
cat_only = {"id": "sc_b", "version": 1, "match": {"sequencing_application": ["BD Rhapsody"],
                                                  "species_in_reference_catalog": True}}
assert M.evaluate(cat_only, order(), MOUSE)["matches"]
assert not M.evaluate(cat_only, order(), {"samples": [{"Species": "Rattus norvegicus"}]})["matches"]
case("species_in_reference_catalog uses the recipe's per-assay family")

# --- select over a catalog
put("sc_a", {"sequencing_application": ["BD Rhapsody"], "samples": {"min": 1, "max": 8}})
put("sc_b", {"sequencing_application": ["10x Genomics Xenium"], "instrument": ["10X Genomics Xenium"]})
assert R.select(order())["id"] == "sc_a"
case("exactly one match -> that recipe is selected")
try:
    R.select(order(sequencingapplication="Transcriptome Sequencing"))
    raise AssertionError("zero matches did not decline")
except R.RecipeError as exc:
    assert "no recipe matches" in str(exc)
case("zero matches -> declined")
put("sc_c", {"sequencing_application": ["Single-Cell - BD Rhapsody"]})
try:
    R.select(order())
    raise AssertionError("two matches did not abstain")
except R.RecipeError as exc:
    assert "2 recipes match" in str(exc) and "abstaining" in str(exc)
case("two matches -> abstain, never a guess")
assert R.select(order(), "sc_b")["id"] == "sc_b"
case("a named recipe is used as named, whatever match says")

print(f"{cases} cases, all pass")
