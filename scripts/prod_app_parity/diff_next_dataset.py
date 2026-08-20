#!/usr/bin/env python3
"""Compare the OUTPUT surface (`next_dataset`) of the allow-listed apps between two
legacy app source trees.

`next_dataset`'s tagged headers are what a downstream app resolves its input against
and what the gStore copy set is derived from, so a change there invalidates a byte-parity
result even when the input surface (which is all the API exposes) is identical.

Reports BOTH kinds of change, because they are independently dangerous:
  * the COLUMN SET changed  -- a header appeared or disappeared;
  * the BODY changed with the same column set -- e.g. a header moved in or out of a
    conditional. STAR on 2026-08-18 is exactly this: `Junctions`/`Chimerics` left
    `if @params['getJunctions']` (which defaulted to false) and became unconditional, so
    the column set alone would have understated the change.

Exits non-zero if any app differs.

    python3 diff_next_dataset.py <baseline_lib_dir> <candidate_lib_dir> [--method next_dataset]
"""
import argparse
import difflib
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# A tagged output column: 'Count [File]', 'IGV [Link,File]', 'DupMetrics [File,Link]' ...
TAG = re.compile(r"""['"]([^'"]*\[[A-Za-z,]*(?:File|Link)[A-Za-z,]*\][^'"]*)['"]""")


def allowlist():
    src = open(os.path.join(REPO, "backend", "config", "application.rb")).read()
    start = src.find("legacy_apps_allowlist")
    if start == -1:
        raise SystemExit("could not find legacy_apps_allowlist in config/application.rb")
    names = []
    for piece in src[start:start + 1200].split("'"):
        for n in piece.split(","):
            n = n.strip()
            if n and n[0].isupper() and n.isalnum():
                names.append(n)
    return sorted(set(names))


def method_body(src, name):
    """Extract `def <name>` .. its matching `end`, by indentation."""
    lines = src.splitlines()
    for i, ln in enumerate(lines):
        m = re.match(r"^(\s*)def\s+%s\b" % re.escape(name), ln)
        if not m:
            continue
        indent = len(m.group(1))
        body = [ln]
        for nxt in lines[i + 1:]:
            body.append(nxt)
            if re.match(r"^\s{%d}end\s*$" % indent, nxt):
                break
        return body
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline", help="app source tree the parity results were validated against")
    ap.add_argument("candidate", help="app source tree that will actually run")
    ap.add_argument("--method", default="next_dataset")
    ap.add_argument("--show-diff", action="store_true", help="print the body diff for each change")
    args = ap.parse_args()

    print("baseline : %s" % args.baseline)
    print("candidate: %s\n" % args.candidate)
    print("%-17s %-9s %s" % ("APP", "VERDICT", "DELTA"))
    print("-" * 100)

    changed, skipped = [], []
    for a in allowlist():
        fb = os.path.join(args.baseline, a + "App.rb")
        fc = os.path.join(args.candidate, a + "App.rb")
        if not (os.path.exists(fb) and os.path.exists(fc)):
            print("%-17s %-9s %s" % (a, "SKIP", "missing on %s" % (
                "baseline" if not os.path.exists(fb) else "candidate")))
            skipped.append(a)
            continue
        bb = method_body(open(fb).read(), args.method)
        bc = method_body(open(fc).read(), args.method)
        if bb is None and bc is None:
            print("%-17s %-9s %s" % (a, "n/a", "neither defines %s" % args.method))
            continue
        if (bb is None) != (bc is None):
            print("%-17s %-9s %s" % (a, "CHANGED", "%s defined on only one side" % args.method))
            changed.append(a)
            continue

        cols_b = sorted(set(TAG.findall("\n".join(bb))))
        cols_c = sorted(set(TAG.findall("\n".join(bc))))
        gone = [c for c in cols_b if c not in cols_c]
        added = [c for c in cols_c if c not in cols_b]
        body_same = " ".join(bb).split() == " ".join(bc).split()

        if not gone and not added and body_same:
            print("%-17s %-9s %s" % (a, "SAME", "columns and body identical"))
            continue

        delta = []
        if gone:
            delta.append("REMOVED " + ", ".join(gone))
        if added:
            delta.append("ADDED " + ", ".join(added))
        if not body_same:
            n = sum(1 for l in difflib.unified_diff(bb, bc, n=0, lineterm="")
                    if l[:1] in "+-" and l[:3] not in ("+++", "---"))
            # Always reported, even when the column set already changed: a header can move
            # in or out of a conditional without the set noticing.
            delta.append("BODY differs (%d lines) -- check conditionals" % n)
        print("%-17s %-9s %s" % (a, "CHANGED", "  |  ".join(delta)))
        changed.append(a)
        if args.show_diff:
            for l in difflib.unified_diff(bb, bc, n=2, lineterm=""):
                if not l.startswith(("---", "+++", "@@")):
                    print("      " + l)

    print("-" * 100)
    print("changed %d | skipped %d" % (len(changed), len(skipped)))
    if changed:
        print("CHANGED -> %s" % ", ".join(changed))
        print("These need Level-2 re-validation: their output dataset shape or the logic "
              "producing it is not what the existing byte-parity results were obtained against.")
    return 1 if changed else 0


if __name__ == "__main__":
    sys.exit(main())
