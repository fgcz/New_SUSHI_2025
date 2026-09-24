#!/usr/bin/env python3
"""How many real B-Fabric orders would the recipe catalog's `match` rules accept?

Order-level only: Species is a dataset column, not an order field, so the two species rules
are reported as "needs the dataset" and every other rule is evaluated exactly as ingest
would (omakase_core/match.py — same canonical form, same fail-closed rules).

Two sets, because they answer different questions:

* orders at status `processed` — what the phase-0 watcher would actually see today;
* sequencing orders created in the last N months — enough volume to show which wordings
  B-Fabric really uses, against the ones the recipes wrote.

Read-only by construction (`client.read` only). Output is aggregate: counts, and the
controlled-vocabulary strings of the order form (sequencing application, instrument). No
order id, label, project, requester or sample name is printed; order records are FGCZ
`internal`.

    python -m omakase_match_audit.audit                # PRODUCTION, 12 months
    python -m omakase_match_audit.audit --months 3 --json out.json
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from bfabric import Bfabric  # noqa: E402

from omakase_core import match, recipes  # noqa: E402
from omakase_metadata_audit.audit import fetch_orders, is_sequencing  # noqa: E402


def evaluate_all(orders, catalog):
    per_order = []
    for o in orders:
        per_order.append([match.evaluate(r, o, None) for r in catalog])
    return per_order


def summarise(name, orders, catalog, per_order):
    n = len(orders)
    passing = [[r["recipe"] for r in res if match.order_level_ok(r)] for res in per_order]
    by_count = Counter(min(len(p), 2) for p in passing)
    per_recipe = Counter(rid for p in passing for rid in p)
    blockers = {r["id"]: Counter() for r in catalog}
    for res in per_order:
        for r in res:
            first = next((k for k, ok, _ in r["checks"] if not ok and k not in match.SPECIES_RULES),
                         None)
            blockers[r["recipe"]][first or "passes at order level"] += 1
    return {
        "set": name, "orders": n,
        "order_level": {"no recipe": by_count.get(0, 0), "exactly one": by_count.get(1, 0),
                        "two or more (abstain)": by_count.get(2, 0)},
        "per_recipe_order_level_pass": {r["id"]: per_recipe.get(r["id"], 0) for r in catalog},
        "first_blocking_rule": {rid: dict(c.most_common()) for rid, c in blockers.items()},
    }


def vocabulary(orders, catalog, field, key, top):
    listed = {match.canonical(v) for r in catalog for v in (r["match"].get(key) or [])}
    counts = Counter(str(o.get(field)).strip() for o in orders
                     if o.get(field) not in (None, "") and str(o.get(field)).strip())
    empty = sum(1 for o in orders if o.get(field) in (None, "") or not str(o.get(field)).strip())
    rows = [{"value": v, "orders": c, "in_a_recipe": match.canonical(v) in listed}
            for v, c in counts.most_common(top)]
    return {"field": field, "distinct": len(counts), "empty": empty, "top": rows,
            "recipe_values_never_seen": sorted({
                v for r in catalog for v in (r["match"].get(key) or [])
                if match.canonical(v) not in {match.canonical(x) for x in counts}})}


def print_summary(s):
    print(f"\n== {s['set']}: {s['orders']} orders")
    for k, v in s["order_level"].items():
        print(f"   {k:<24} {v:>5}  ({100 * v / s['orders']:.1f}%)" if s["orders"] else "")
    hit = {k: v for k, v in s["per_recipe_order_level_pass"].items() if v}
    print("   per recipe (order-level pass): " + (", ".join(f"{k} {v}" for k, v in hit.items())
                                                  or "none"))


def print_vocab(v):
    print(f"\n-- {v['field']}: {v['distinct']} distinct values, {v['empty']} orders empty")
    for row in v["top"]:
        mark = "in a recipe" if row["in_a_recipe"] else "-"
        print(f"   {row['orders']:>5}  {row['value'][:70]:<70}  {mark}")
    print(f"   recipe values never seen in these orders ({len(v['recipe_values_never_seen'])}): "
          + "; ".join(v["recipe_values_never_seen"]))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--env", default="PRODUCTION", choices=["PRODUCTION", "TEST"])
    ap.add_argument("--months", type=float, default=12)
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--json", type=Path)
    args = ap.parse_args()

    catalog = [recipes.load(i) for i in recipes.available()]
    catalog = [r for r in catalog if r["source"] == "catalog"]
    if not catalog:
        print("no catalog recipes found (OMAKASE_CATALOG_DIR)", file=sys.stderr)
        return 2
    client = Bfabric.connect(config_file_env=args.env)
    processed = list(client.read("order", {"status": "processed"}, max_results=None))
    recent, since = fetch_orders(client, args.months)
    recent = [o for o in recent if is_sequencing(o)]

    out = {"env": args.env, "catalog": [f"{r['id']}@{r['version']}" for r in catalog],
           "since": since, "summaries": [], "vocabulary": []}
    for name, orders in ((f"status=processed ({args.env})", processed),
                         (f"sequencing orders created since {since[:10]}", recent)):
        s = summarise(name, orders, catalog, evaluate_all(orders, catalog))
        out["summaries"].append(s)
        print_summary(s)
    for field, key in (("sequencingapplication", "sequencing_application"),
                       ("instrument", "instrument")):
        v = vocabulary(recent, catalog, field, key, args.top)
        out["vocabulary"].append(v)
        print_vocab(v)
    if args.json:
        args.json.write_text(json.dumps(out, indent=2, ensure_ascii=False))
        print(f"\nwritten: {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
