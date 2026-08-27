#!/usr/bin/env python3
"""OMAKASE step 1 (design §17): metadata-readiness audit of B-Fabric orders.

Answers one question: **for how many real orders could a recipe be selected from
order metadata alone today?** That number decides whether OMAKASE is worth
building, so this script is deliberately dumb - it counts fields, it does not
interpret them, and it never calls an LLM.

Read-only by construction: the only B-Fabric call used is `read`. Nothing is
written to B-Fabric, to gStore, or to the SUSHI database.

Output is aggregate only. Order labels, project names, requester names and
sample names are never printed, because order records are FGCZ `internal` and
the audit does not need them.

Usage:
    python audit.py                      # last 12 months, production
    python audit.py --months 3
    python audit.py --env TEST           # smoke test against the test instance
    python audit.py --json out.json      # also write machine-readable output

Requires bfabricPy (present in gi_py3.12.8) and ~/.bfabricpy.yml.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta

from bfabric import Bfabric

# The L0 allow-list from design §3.1, mapped to the field names the B-Fabric
# order endpoint actually returns. Verified against production on 2026-08-20.
#
# "Species" is deliberately absent: it does not exist on the order endpoint
# (49 fields) nor on the sample endpoint (13 fields). See SPECIES_NOTE.
ALLOW_LIST = [
    # (report label, order field, is it required to pick a recipe?)
    ("Service Type", "servicetype", True),
    ("Sequencing Application", "sequencingapplication", True),
    ("Instrument", "instrument", False),
    ("Library Protocol", "libraryprotocol", False),
    ("Sample count (declared)", "numberofsamples", False),
    ("Sample count (derived)", "countsamples", False),
]

# Fields that must be usable before a recipe can be chosen at all. Instrument
# and library protocol refine a choice; they do not make it.
REQUIRED_FOR_RECIPE = ["servicetype", "sequencingapplication"]

SPECIES_NOTE = (
    "Species is NOT available in B-Fabric order metadata. Probed 2026-08-20 "
    "against production: the order endpoint returns 49 fields and the sample "
    "endpoint 13, and none matches species / organism / taxon / strain. In "
    "SUSHI, Species is a dataset COLUMN (many legacy apps declare it in "
    "required_columns), i.e. it appears only after a dataset exists. A recipe "
    "that resolves a reference genome therefore cannot do so from the order "
    "alone."
)

# A value that says "the vocabulary did not fit" is worse than an empty one:
# it looks filled to any completeness check while carrying no decision content.
VAGUE_MARKERS = ("custom", "other", "misc", "unknown", "n/a", "na", "tbd", "-")

TECHNOLOGY_SEQUENCING = "Genomics"


def classify(value) -> str:
    """present | vague | empty - the three states the audit distinguishes."""
    if value is None or value == "" or value == [] or value == {}:
        return "empty"
    if isinstance(value, dict):
        return "present" if value.get("id") else "empty"
    if isinstance(value, (int, float)):
        return "present" if value else "empty"
    text = str(value).strip().lower()
    if not text:
        return "empty"
    # Match whole words so "Other" is vague but "Mother" or "Custom Kit XY"
    # are judged on their own terms.
    words = {w.strip("()[]/,.") for w in text.replace("-", " ").split()}
    if words & set(VAGUE_MARKERS) or text in VAGUE_MARKERS:
        return "vague"
    return "present"


def service_type_names(client, ids):
    """Resolve service-type ids to names. Falls back to the bare id."""
    names = {}
    if not ids:
        return names
    try:
        for row in client.read("servicetype", {"id": sorted(ids)}, max_results=None):
            names[int(row["id"])] = row.get("name") or f"id={row['id']}"
    except Exception as exc:  # noqa: BLE001
        print(f"  ! could not resolve service-type names: {exc}", file=sys.stderr)
    return names


def fetch_orders(client, months):
    since = (datetime.now() - timedelta(days=int(months * 30.44))).strftime(
        "%Y-%m-%d 00:00:00"
    )
    print(f"reading orders created after {since} ...", file=sys.stderr)
    orders = list(client.read("order", {"createdafter": since}, max_results=None))
    print(f"  {len(orders)} orders", file=sys.stderr)
    return orders, since


def is_sequencing(order) -> bool:
    tech = order.get("technology") or []
    if isinstance(tech, str):
        tech = [tech]
    return any(TECHNOLOGY_SEQUENCING in str(t) for t in tech)


def audit(orders, st_names):
    """Return (overall, per_service_type) tallies."""
    overall = {field: Counter() for _, field, _ in ALLOW_LIST}
    per_st = defaultdict(lambda: {"n": 0, **{f: Counter() for _, f, _ in ALLOW_LIST}})
    addressable = Counter()

    for o in orders:
        st = o.get("servicetype")
        st_id = int(st["id"]) if isinstance(st, dict) and st.get("id") else 0
        st_label = st_names.get(st_id, f"id={st_id}" if st_id else "(no service type)")
        bucket = per_st[st_label]
        bucket["n"] += 1

        for _, field, _ in ALLOW_LIST:
            state = classify(o.get(field))
            overall[field][state] += 1
            bucket[field][state] += 1

        usable = all(classify(o.get(f)) == "present" for f in REQUIRED_FOR_RECIPE)
        addressable["yes" if usable else "no"] += 1
        bucket.setdefault("addressable", Counter())["yes" if usable else "no"] += 1

    return overall, per_st, addressable


def pct(n, total):
    return f"{100.0 * n / total:5.1f}%" if total else "    -"


def normalise(text):
    """Lowercased alphanumeric tokens - the form a recipe predicate would match on."""
    cleaned = "".join(ch if ch.isalnum() else " " for ch in str(text).lower())
    return frozenset(cleaned.split())


def vocabulary_report(orders, field="sequencingapplication"):
    """List the controlled vocabulary actually in use, and flag near-duplicates.

    A recipe match predicate keys off these strings, so two spellings of the
    same application are two recipes that must be kept in sync - or one that
    silently fails to match. Worth knowing before any recipe is written.
    """
    counts = Counter()
    for o in orders:
        v = o.get(field)
        if classify(v) == "present":
            counts[str(v).strip()] += 1
    if not counts:
        return

    print(f"\n## Vocabulary in use: {field} ({len(counts)} distinct values)\n")
    for value, n in counts.most_common():
        print(f"  {n:>5}  {value}")

    # Two entries for one real application. A generic "is one a subset of the
    # other" test is useless here - it also pairs "SARS-CoV-2 Whole Genome
    # Sequencing" with "Whole Genome Sequencing", which are different services.
    # So only two narrow, defensible signals are reported:
    #
    #   A. identical except a leading category word ("Single-Cell - ",
    #      "Spatial - ") that the rest of the string already implies;
    #   B. exactly one token differs and those two tokens are near-identical,
    #      which is a spelling mistake rather than a different application.
    import difflib

    category_words = {"single", "cell", "spatial", "sc", "bulk"}
    values = list(counts)
    dupes = []
    for i, a in enumerate(values):
        for b in values[i + 1:]:
            ta, tb = normalise(a), normalise(b)
            if ta == tb:
                dupes.append((counts[a] + counts[b], a, b, "identical tokens"))
                continue
            if ta < tb or tb < ta:
                extra = (tb - ta) if ta < tb else (ta - tb)
                if extra <= category_words:
                    dupes.append(
                        (counts[a] + counts[b], a, b, "only a category prefix differs")
                    )
                continue
            # Neither contains the other. It can still be one application if a
            # single token is misspelled - possibly on top of a category prefix,
            # which is why the category residue is set aside before comparing.
            #
            # The residue is required to be empty on ONE side. Without that,
            # "Single-Cell - X" and "Bulk - X" would pair up, and that is a
            # real distinction rather than a duplicate.
            only_a, only_b = ta - tb, tb - ta
            word_a, word_b = only_a - category_words, only_b - category_words
            residue_a, residue_b = only_a & category_words, only_b & category_words
            if (
                len(word_a) == 1
                and len(word_b) == 1
                and (not residue_a or not residue_b)
            ):
                wa, wb = next(iter(word_a)), next(iter(word_b))
                if difflib.SequenceMatcher(None, wa, wb).ratio() > 0.8:
                    dupes.append(
                        (counts[a] + counts[b], a, b, f"spelling: {wa!r} vs {wb!r}")
                    )

    if dupes:
        print(f"\n## Duplicate vocabulary entries ({len(dupes)} pairs)\n")
        print("  Each pair is two menu entries a recipe would have to match")
        print("  separately, for what looks like one application.\n")
        for total, a, b, why in sorted(dupes, reverse=True):
            print(f"  {total:>5} orders  [{why}]")
            print(f"          {a}")
            print(f"          {b}")
    else:
        print("\n## Duplicate vocabulary entries: none found\n")


def print_report(title, orders, overall, per_st, addressable, since):
    total = len(orders)
    print()
    print("=" * 78)
    print(f"{title}  -  {total} orders created after {since[:10]}")
    print("=" * 78)
    if not total:
        print("no orders in scope")
        return

    print("\n## Field readiness (all orders in scope)\n")
    print(f"{'field':28} {'present':>16} {'Custom/Other':>16} {'empty':>16}")
    print("-" * 78)
    for label, field, required in ALLOW_LIST:
        c = overall[field]
        mark = " *" if required else "  "
        print(
            f"{label + mark:28} "
            f"{c['present']:>6} {pct(c['present'], total):>9} "
            f"{c['vague']:>6} {pct(c['vague'], total):>9} "
            f"{c['empty']:>6} {pct(c['empty'], total):>9}"
        )
    print("\n  * = required before a recipe can be selected at all")

    yes, no = addressable["yes"], addressable["no"]
    print("\n## The number that decides the project\n")
    print(f"  orders where every required field is usable : {yes:>6}  {pct(yes, total)}")
    print(f"  orders where at least one is missing/vague  : {no:>6}  {pct(no, total)}")

    print("\n## Per service type (by volume)\n")
    header = f"{'service type':46} {'n':>5} {'addressable':>12}"
    print(header)
    print("-" * len(header))
    for label, b in sorted(per_st.items(), key=lambda kv: -kv[1]["n"]):
        a = b.get("addressable", Counter())
        name = label if len(label) <= 45 else label[:42] + "..."
        print(f"{name:46} {b['n']:>5} {a['yes']:>5} {pct(a['yes'], b['n']):>7}")

    print("\n## Where the required fields fail, per service type\n")
    print(f"{'service type':40} {'seq. application: vague/empty':>30}")
    print("-" * 72)
    for label, b in sorted(per_st.items(), key=lambda kv: -kv[1]["n"])[:15]:
        c = b["sequencingapplication"]
        bad = c["vague"] + c["empty"]
        name = label if len(label) <= 39 else label[:36] + "..."
        print(f"{name:40} {bad:>6} / {b['n']:<6} {pct(bad, b['n']):>9}")

    vocabulary_report(orders)

    print(f"\n## Species\n\n  {SPECIES_NOTE}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--months", type=float, default=12.0)
    ap.add_argument("--env", default="PRODUCTION", help="bfabricpy config env")
    ap.add_argument("--json", dest="json_out", default=None)
    args = ap.parse_args()

    client = Bfabric.from_config(config_env=args.env)
    print(f"instance: {client.config.base_url}", file=sys.stderr)

    orders, since = fetch_orders(client, args.months)
    if not orders:
        print("no orders returned - nothing to audit", file=sys.stderr)
        return 1

    st_ids = {
        int(o["servicetype"]["id"])
        for o in orders
        if isinstance(o.get("servicetype"), dict) and o["servicetype"].get("id")
    }
    st_names = service_type_names(client, st_ids)

    seq = [o for o in orders if is_sequencing(o)]

    results = {}
    for title, subset in (
        ("ALL ORDERS", orders),
        (f"SEQUENCING ONLY (technology contains '{TECHNOLOGY_SEQUENCING}')", seq),
    ):
        overall, per_st, addressable = audit(subset, st_names)
        print_report(title, subset, overall, per_st, addressable, since)
        results[title] = {
            "orders": len(subset),
            "fields": {f: dict(overall[f]) for _, f, _ in ALLOW_LIST},
            "addressable": dict(addressable),
            "per_service_type": {
                k: {
                    "n": v["n"],
                    "addressable": dict(v.get("addressable", {})),
                    "fields": {f: dict(v[f]) for _, f, _ in ALLOW_LIST},
                }
                for k, v in per_st.items()
            },
        }

    if args.json_out:
        payload = {
            "generated_from": client.config.base_url,
            "since": since,
            "months": args.months,
            "species_note": SPECIES_NOTE,
            "results": results,
        }
        with open(args.json_out, "w") as fh:
            json.dump(payload, fh, indent=2, sort_keys=True)
        print(f"wrote {args.json_out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
