#!/usr/bin/env python3
"""Species -> refBuild, against a fixture farm. rc 0 = the refusals happen.

Most of these cases are refusals on purpose. The happy path is one line of dictionary
lookup and cannot really break; what can break is a refusal quietly turning into a default,
and that is the failure that produces a directory of near-zero counts nobody questions.

The fixture farm mirrors the real one's shape -- `<species>/<provider>/<assembly>/
Annotation/<release>/Genes` -- including the `Annotation/Genes` convenience symlink that
Arabidopsis carries in production, because mistaking that for a release is the one
structural mistake available here.
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    __package__ = "omakase_core"

from . import recipes, reference  # noqa: E402

FIXTURE = [
    "Arabidopsis_thaliana/TAIR/TAIR10/Annotation/Release_57-2023-09-06",
    "Mus_musculus/GENCODE/GRCm39/Annotation/Release_M37-2025-07-03",
    "Homo_sapiens/GENCODE/GRCh38.p14/Annotation/Release_48-2025-07-03",
]

failures: list[str] = []


def check(name: str, got, want) -> None:
    if got == want:
        print(f"  ok   {name}")
    else:
        failures.append(name)
        print(f"  FAIL {name}: got {got!r}, want {want!r}")


def refuses(name: str, fn, must_mention: str) -> None:
    try:
        got = fn()
    except reference.ReferenceError as exc:
        if must_mention.lower() in str(exc).lower():
            print(f"  ok   {name}")
        else:
            failures.append(name)
            print(f"  FAIL {name}: refused, but the reason never says "
                  f"{must_mention!r}: {exc}")
        return
    failures.append(name)
    print(f"  FAIL {name}: did not refuse, returned {got!r}")


def build_farm(root: Path) -> None:
    for rel in FIXTURE:
        (root / rel / "Genes").mkdir(parents=True)
    # The production shortcut: Arabidopsis carries Annotation/Genes -> <release>/Genes.
    # It is a directory with no `Genes` inside, so it must not be counted as a release.
    (root / "Arabidopsis_thaliana/TAIR/TAIR10/Annotation/Genes").mkdir()


def dataset(*species: str | None) -> dict:
    """A dataset shaped like `GET /api/v1/datasets/:id`. `None` = the column is absent."""
    return {"samples": [{"Name": f"s{i}", **({} if sp is None else {"Species": sp})}
                        for i, sp in enumerate(species)]}


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        build_farm(root)

        print("catalog")
        cat = reference.builds(root)
        check("three species, not four (Annotation/Genes is not a release)", len(cat), 3)
        check("keyed case- and separator-insensitively",
              cat.get("mus musculus"),
              ["Mus_musculus/GENCODE/GRCm39/Annotation/Release_M37-2025-07-03"])

        print("resolution")
        check("the live case: dataset 9 says Mus musculus",
              reference.resolve_for_dataset(dataset("Mus musculus", "Mus musculus"), root)[0],
              "Mus_musculus/GENCODE/GRCm39/Annotation/Release_M37-2025-07-03")
        check("underscores and case do not matter",
              reference.resolve(["mus_musculus"], root),
              "Mus_musculus/GENCODE/GRCm39/Annotation/Release_M37-2025-07-03")
        check("the derivation is stated, not just the value",
              "Species=Mus musculus" in
              reference.resolve_for_dataset(dataset("Mus musculus"), root)[1],
              True)

        print("wording (2026-10-02: B-Fabric names carry the common name)")
        mouse = "Mus_musculus/GENCODE/GRCm39/Annotation/Release_M37-2025-07-03"
        check("'Mus musculus (house mouse)' -- 289 production datasets -- resolves",
              reference.resolve(["Mus musculus (house mouse)"], root), mouse)
        check("'Human' and 'Mouse' resolve through the alias table",
              (reference.resolve(["Human"], root), reference.resolve(["Mouse"], root)),
              ("Homo_sapiens/GENCODE/GRCh38.p14/Annotation/Release_48-2025-07-03", mouse))
        check("the bracketed and the bare wording are ONE species, not two",
              reference.resolve_for_dataset(
                  dataset("Mus musculus (house mouse)", "Mus musculus"), root)[0], mouse)
        refuses("an uncurated species with a common name is still refused",
                lambda: reference.resolve(["Danio rerio (zebrafish)"], root), "not one of")
        refuses("a bracket in the middle is not a common-name suffix",
                lambda: reference.resolve(["Mus (house) musculus"], root), "not one of")
        refuses("free text naming a cell type is not a species",
                lambda: reference.resolve(["mouse Kupffer cells"], root), "not one of")

        print("refusals -- the reason this file exists")
        refuses("no Species column at all",
                lambda: reference.resolve_for_dataset(dataset(None, None), root), "no usable")
        refuses("Species present but NA, which is 39.2% of production datasets",
                lambda: reference.resolve_for_dataset(dataset("NA", "n/a"), root), "no usable")
        refuses("two species in one dataset, which is 5.7% of production datasets",
                lambda: reference.resolve_for_dataset(
                    dataset("Mus musculus", "Homo sapiens"), root), "2 species")
        refuses("a species the farm does not carry",
                lambda: reference.resolve(["Danio rerio"], root), "not one of the 3 curated")
        refuses("an unreadable farm is not an empty farm",
                lambda: reference.resolve(["Mus musculus"], root / "does-not-exist"),
                "unreadable or empty")

        print("the recipe engine's sentinel")
        steps = [
            {"seq": 1, "app_name": "STARApp",
             "parameters": {"ram": 30, "refBuild": recipes.FROM_SPECIES},
             "retry_parameters": {"ram": 60, "refBuild": recipes.FROM_SPECIES}},
            {"seq": 2, "app_name": "FeatureCountsApp", "depends_on_seq": 1,
             "parameters": {"ram": 20}},
        ]
        got, notes = reference_expand(steps, dataset("Mus musculus"), root)
        want = "Mus_musculus/GENCODE/GRCm39/Annotation/Release_M37-2025-07-03"
        check("parameters expanded", got[0]["parameters"]["refBuild"], want)
        check("retry_parameters expanded too -- a retry must not lose the genome",
              got[0]["retry_parameters"]["refBuild"], want)
        check("a step without the sentinel is untouched", got[1]["parameters"], {"ram": 20})
        check("the farm is read once, not once per sentinel", len(notes), 1)
        check("the recipe on disk is not mutated", steps[0]["parameters"]["refBuild"],
              recipes.FROM_SPECIES)

        refuses("a dataset that cannot answer stops the proposal, not the submission",
                lambda: reference_expand(steps, dataset("Danio rerio"), root), "not one of")

    print()
    if failures:
        print(f"FAILED: {len(failures)} case(s): {', '.join(failures)}")
        return 1
    print("all reference cases pass")
    return 0


def reference_expand(steps, ds, root):
    """`recipes.resolve_parameters` with the farm pointed at the fixture."""
    original, reference.FAVORITE_ROOT = reference.FAVORITE_ROOT, root
    try:
        return recipes.resolve_parameters(steps, ds)
    finally:
        reference.FAVORITE_ROOT = original


if __name__ == "__main__":
    sys.exit(main())
