# omakase_match_audit

**How many real B-Fabric orders would the recipe catalog's `match` rules accept?**

Read-only (`client.read` only), aggregate output, no model. It evaluates every catalog
recipe against real orders with the engine's own matcher (`omakase_core/match.py`: the same
canonical form and the same fail-closed rules ingest uses), at ORDER level — Species is a
dataset column, so the two species rules are reported as "needs the dataset" and every
other rule is evaluated.

```
cd scripts && python3 -m omakase_match_audit.audit                 # PRODUCTION, 12 months
python3 -m omakase_match_audit.audit --months 3 --json out.json
```

Two sets: orders at `processed` (what the phase-0 watcher sees) and sequencing orders of
the last N months (enough volume to show the vocabulary actually in use).

## Result, 2026-09-24 (PRODUCTION, catalog = Paul Gueguen's MR !1, 12 recipes)

| set | orders | no recipe | exactly one | two or more |
|---|---|---|---|---|
| status `processed` | 30 | 30 | 0 | 0 |
| sequencing orders since 2025-09-24 | 1467 | 1467 | 0 | 0 |

**Zero, for two reasons, neither of them in the engine:**

1. **Sequencing application wording.** 18 of the catalog's 19 distinct values never occur
   in the 1467 orders; B-Fabric's form uses its own menu wording. Only `BD Rhapsody`
   occurs (31 orders, via the category-prefix fold of `Single-Cell - BD Rhapsody`). 11 of
   the 12 recipes are blocked here for every order.
2. **Instrument granularity.** The catalog writes platforms (`Illumina`, `AVITI`,
   `Xenium`); B-Fabric records models (11 distinct, e.g. `Illumina NovaSeq X Plus`). Exact
   comparison therefore fails for every order, including the 31 BD Rhapsody ones.

The engine is deliberately not "fixed" to match anyway: containment was rejected by the
2026-08-20 metadata audit because it pairs different services. The wording is the recipe
author's decision — this script lists the values that exist so it can be made.
