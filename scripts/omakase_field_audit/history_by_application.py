#!/usr/bin/env python3
"""What did FGCZ actually run, per B-Fabric Sequencing Application?

Joins the execution-history table written by `omakase_history_audit` (order id, chain depth,
SUSHI app; from the 082 SUSHI database) with each order's Sequencing Application read from
B-Fabric. Prints, per application: how many orders, which apps ran on what share of them,
and the commonest chains. It is evidence for whoever drafts a recipe — not an oracle: older
analyses may use workflows that are no longer current (design §5.3).

Read-only (`read` only). No LLM. Aggregate output: application and app names are controlled
vocabulary; order ids, projects and people are never printed. A chain is printed only when at
least --min-count orders share it.

    python -m omakase_field_audit.history_by_application ~/.omakase/audit/omakase_history_082.tsv
"""
from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter, defaultdict

from bfabric import Bfabric


def load_history(path):
    by_order = defaultdict(lambda: defaultdict(set))
    with open(path, encoding="utf-8") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            oid = int(row["order_id"])
            if oid > 0:
                by_order[oid][int(row["depth"])].add(row["sushi_app_name"])
    return by_order


def shape(depths):
    return " => ".join("{" + ",".join(sorted(depths[d])) + "}" for d in sorted(depths))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("tsv")
    ap.add_argument("--env", default="PRODUCTION")
    ap.add_argument("--min-count", type=int, default=3)
    ap.add_argument("--min-orders", type=int, default=5, help="applications with fewer are pooled")
    args = ap.parse_args(argv)
    if args.min_count < 3:
        ap.error("--min-count below 3 would print near-unique chains")

    hist = load_history(args.tsv)
    client = Bfabric.from_config(config_env=args.env)
    ids = sorted(hist)
    apps = {}
    for i in range(0, len(ids), 100):
        for o in client.read("order", {"id": ids[i:i + 100]}, max_results=None):
            apps[int(o["id"])] = str(o.get("sequencingapplication") or "(none)").strip()
    groups = defaultdict(list)
    for oid in ids:
        groups[apps.get(oid, "(order not readable)")].append(oid)
    print(f"orders in the history table: {len(ids)}; resolved in B-Fabric: {len(apps)}")
    small = 0
    for app_name, oids in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        n = len(oids)
        if n < args.min_orders:
            small += n
            continue
        # each app once per order, whatever depth(s) it ran at
        used = Counter(a for o in oids for a in set().union(*hist[o].values()))
        shapes = Counter(shape(hist[o]) for o in oids)
        print(f"\n== {app_name}: {n} orders")
        print("   apps (share of orders): " + ", ".join(
            f"{a} {100 * k // n}%" for a, k in used.most_common(12)))
        for s, k in shapes.most_common(4):
            if k >= args.min_count:
                print(f"   {k:4}  {s}")
    print(f"\n(applications with fewer than {args.min_orders} orders, pooled: {small} orders)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
