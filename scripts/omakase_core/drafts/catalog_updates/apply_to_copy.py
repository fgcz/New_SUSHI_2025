#!/usr/bin/env python3
"""Apply match_v2.yaml to a TEMPORARY copy of the catalog, so the proposal can be measured.

The catalog is Paul Gueguen's work in his own repository and is not published; this script
never writes into it and never copies it into this repository. It prints the copy's path:

    COPY=$(python3 apply_to_copy.py)
    OMAKASE_CATALOG_DIR=$COPY python -m omakase_match_audit.audit --source catalog

Each changed recipe becomes `<id>_v<N+1>.yaml` with only its `match:` block replaced; the
loader picks the highest version, so the copy measures exactly the proposal.
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
DEFAULT_CATALOG = Path("/srv/sushi/masa_test_new_sushi_20260527/paul-scripts/Internal_Dev/omakase")


def main() -> int:
    src = Path(os.environ.get("OMAKASE_CATALOG_DIR") or DEFAULT_CATALOG)
    proposal = yaml.safe_load((HERE / "match_v2.yaml").read_text(encoding="utf-8"))["recipes"]
    dst = Path(tempfile.mkdtemp(prefix="omakase_catalog_v2_"))   # mode 700
    shutil.copytree(src, dst, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(".git", "__pycache__"))
    changed = 0
    for path in sorted((dst / "recipes").glob("*_v*.yaml")):
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        if raw.get("id") not in proposal:
            continue
        raw["match"] = proposal[raw["id"]]
        raw["version"] = int(raw["version"]) + 1
        out = path.with_name(f"{raw['id']}_v{raw['version']}.yaml")
        out.write_text(yaml.safe_dump(raw, sort_keys=False, allow_unicode=True), encoding="utf-8")
        path.unlink()
        changed += 1
    print(f"{changed} recipe(s) rewritten", file=sys.stderr)
    print(dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
