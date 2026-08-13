# Production app-usage snapshot (fgcz-h-082)

How much of the **real** legacy workload the allow-listed apps cover. This exists because
counting files is misleading: "17 of 112 apps" reads as 15% coverage, but measured by usage
those 17 apps served ~83% of recent production datasets. Allow-list priorities should be set
from this, not from the file count.

`analyze_coverage.py` reads the allow-list straight out of `backend/config/application.rb`,
so it cannot drift from the code — re-run it after any allow-list change.

## Run

```bash
python3 scripts/prod_app_usage/analyze_coverage.py
```

No database, no network — it only reads the two snapshots in this directory. Override with
`USAGE_TSV=`, `PROD_APPS=`, `APP_CONFIG=`.

## Result 2026-08-13 (allow-list = 18 apps, after CellRanger was added)

| window | all datasets | by still-live apps | covered | % of all | % of live |
|--------|-------------:|-------------------:|--------:|---------:|----------:|
| all-time  | 54873 | 51618 | 47485 | 86.5% | 92.0% |
| 2025+2026 | 10525 | 10367 |  8858 | 84.2% | 85.4% |
| 2026 only |  3698 |  3661 |  3096 | 83.7% | 84.6% |

Marginal value collapses fast: the top-5 uncovered apps buy 89.3%, top-10 92.1%, top-20 94.9%
of live-app usage. Beyond ~10 each app buys well under half a percent.

**Scope**: 207 app class names have ever produced a dataset in production, but only **110
still have an `*App.rb`** in prod master. The 97 retired names are not portable by
definition; they account for just 1.5% of 2025+2026 usage, which is why the "% of live"
column is the honest one.

## Re-taking the snapshot

Only if it must be refreshed — this is a **production** database. Read-only, no DDL, no
write, and **never** `db:migrate` on 082. Get explicit go-ahead first.

```bash
ssh fgcz-h-082
set -a; . /etc/sushi/secret.env; set +a          # holds SUSHI_DB_PASSWORD only
export MYSQL_PWD="$SUSHI_DB_PASSWORD"
mysql --socket=/var/run/mysqld/mysqld.sock -u sushilover sushi --batch -e "
SELECT CAST(sushi_app_name AS BINARY) AS app, COUNT(*) AS total,
       MAX(created_at) AS last_used,
       SUM(created_at >= '2026-01-01') AS y2026,
       SUM(created_at >= '2025-01-01' AND created_at < '2026-01-01') AS y2025
FROM data_sets
WHERE sushi_app_name IS NOT NULL AND sushi_app_name <> ''
GROUP BY CAST(sushi_app_name AS BINARY) ORDER BY total DESC;"   # -> app_usage_082_<date>.tsv

ls /srv/sushi/production/master/lib/*App.rb | xargs -n1 basename | sed 's/\.rb$//'
                                                                # -> prod_master_apps_<date>.txt
```

One full scan of `data_sets` (~82k rows) plus a `GROUP BY`. Keep it that cheap: 082 is a
15 GB submit node with no swap. `jobs` has no app-name column, so corroborating there would
mean a join over 472k rows — deliberately not done.

### Two traps that cost real time — do not relearn them

1. **`GROUP BY` on this DB is case-insensitive** (`utf8mb4_general_ci`) and MySQL returns an
   **arbitrary representative spelling** for each merged group. The first run reported
   `SCSeuratApp` with 77 datasets in 2026 — a name that exists **nowhere** on disk. Grouping
   by `CAST(... AS BINARY)` resolved it: `ScSeuratApp` (597) + `SCSeuratApp` (91), a
   historical rename merged under the old label. The merge is what we want (renames are one
   app); the *label* was the lie. Hence the `CAST` in the query above, and the
   case-insensitive re-grouping in the script.
2. **Match against prod master, not a test checkout.** The first pass used
   `/srv/sushi/masa_test_sushi_20260416/master/lib` (2026-04-16). It differs from prod:
   prod has `ChIPSeqPeakComparisonApp` and `SplitPipeApp`, the test checkout has `DnaQCApp`
   — which prod lacks despite `DnaQCApp` datasets as recent as 2026-06-25.

## Method caveat

`data_sets` counts **app submissions**: legacy writes exactly one next-dataset per submit,
regardless of SAMPLE-mode fan-out. So this measures *how often an app is run*, which is the
right metric for allow-list ordering. It does not count failed runs that produced no dataset,
nor compute volume.
