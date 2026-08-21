# OMAKASE decision D-a — where does Species come from, and can a reference be resolved?

Companion to `scripts/omakase_metadata_audit` (design §17 step 1). That audit found that
**Species does not exist in B-Fabric order metadata at all**, which left design §3.1
(Species on the allow-list) and §5 (`refBuild` resolved from Species) with no source.
Three exits were on the table; this directory measures which of them actually works.

Two scripts, both read-only, no LLM, aggregate output only:

| Script | Question |
|---|---|
| `species_audit.py` | Do the Species values in SUSHI datasets resolve to a reference build? |
| `crosscheck_order_service_type.py` | Which service types are the unusable ones from? |

## What was measured

**Population**: SUSHI datasets created in the 12 months to 2026-08-21 that were
*registered rather than produced by an app* (`sushi_app_name` empty) and carry an
`order_id` — i.e. the raw data a finished order delivers, which is exactly what the
OMAKASE trigger would see. **1376 datasets behind 974 distinct orders.**

### 1. The Species column is filled, but a third of it says nothing

| state | datasets | share |
|---|---:|---:|
| Species column carries text | 1358 | 98.7% |
| whitespace / no value | 18 | 1.3% |

98.7% is the wrong number to quote. Classified by content:

| verdict | datasets | share | distinct spellings |
|---|---:|---:|---:|
| resolvable — a curated recommended build exists | 712 | 51.7% | 8 |
| resolvable only via an **unreviewed alias** | 39 | 2.8% | 9 |
| in the catalog, but no curated build (a human picks) | 59 | 4.3% | 10 |
| names a species with no reference in the catalog | 26 | 1.9% | 11 |
| **no usable value** (`NA`, `n/a`, `Unidentified`, blank) | **540** | **39.2%** | 4 |

`NA` (297) and `n/a` (215) are the SUSHI equivalent of B-Fabric's `Custom / Other`: they
pass any "is the field filled?" check and carry no decision content.

Also measured: **79 datasets (5.7%) contain more than one Species value**, so a single
`refBuild` cannot cover them. A recipe must either fan out per sample or refuse.

### 2. The gap is one service type — the same one as on the B-Fabric side

| service type | datasets | Species unusable | share |
|---|---:|---:|---:|
| Ready-made Libraries Sequencing | 714 | 414 | 58.0% |
| High Throughput Sequencing (NGS) | 440 | 100 | 22.7% |
| Single Cell Sequencing | 99 | 4 | 4.0% |
| Spatial Gene Expression | 60 | 5 | 8.3% |
| Genome Informatics | 38 | 8 | 21.1% |
| CRISPR Screen | 7 | 4 | 57.1% |
| Long Read Sequencing | 2 | 2 | 100.0% |
| (order not readable) | 12 | 3 | 25.0% |
| Protein Analysis Services | 4 | 0 | 0.0% |
| **TOTAL** | **1376** | **540** | **39.2%** |

**Ready-made Libraries Sequencing alone accounts for 76.7% of every unusable value.**
That is the same service type the B-Fabric audit found at 22.8% usable, for the same
underlying reason: FGCZ did not prepare the library, so nobody filled the fields in. One
field change on one service type moves both numbers.

Excluding that service type, 536 of 662 datasets (81.0%) carry a specific species.

### 3. Species → refBuild is a lookup table that already exists

`/srv/GT/reference-favorite` holds a **human-curated recommended build per species**,
maintained by the reference owners, and SUSHI already lists it at the top of the
`refBuild` dropdown. Five species today:

```
Homo_sapiens/GENCODE/GRCh38.p14/Annotation/Release_48-2025-07-03
Mus_musculus/GENCODE/GRCm39/Annotation/Release_M37-2025-07-03
Rattus_norvegicus/Ensembl/GRCr8/Annotation/Release_114-2025-07-03
Canis_familiaris/Ensembl/ROS_Cfam_1.0/Annotation/Release113-2025-07-02
Arabidopsis_thaliana/TAIR/TAIR10/Annotation/Release_57-2023-09-06
```

This is the implementation of `{{ reference_for(species) }}` in design §5.1 — OMAKASE does
not need to invent a species→build policy, and it must not: the choice of build is a
domain decision that already has an owner. Those five species account for 712 of the 836
datasets that name a specific species — 85.2%.

The wider catalog (`/srv/GT/reference`, `/srv/GT/assembly`) offers builds under 140
top-level directories, but not all are species — it also holds control sequences, project
specific references and collections (`PhiX`, `Bacteria`, `p27821`, …). A species there
without a curated pick has 1–4 candidate builds, so a human still chooses.

### 4. Spelling drift is already present on the SUSHI side

The same problem D-b records for B-Fabric's Sequencing Application vocabulary:

| species | spellings in 12 months |
|---|---|
| human | `Homo sapiens` 352, `Human` 23, `Homo sapiens (human)` 18, `Homo_sapiens` 1 |
| mouse | `Mus musculus (house mouse)` 289, `Mus musculus` 17, `Mouse` 1 |
| dog | `Canis familiaris` 18, `Canis lupus familiaris` 6 |
| yeast | `Saccharomyces cerevisiae` 3, `… (bakers yeast)` 3, `Saccharomyces cerevisiaeNA` 1 |
| pig | `Sus scrofa` 18, `Sus Linnaeus (Pig)` 2 |

`species_audit.py` handles only what a **syntactic** rule can handle — dropping one
trailing parenthetical common name, and whitespace/separator normalisation. Anything
requiring a claim about biology (`Human` = `Homo_sapiens`, `Canis lupus familiaris` =
`Canis_familiaris`) sits in `ALIASES_NEEDING_SIGNOFF` and is **counted separately**, so
the headline 51.7% never depends on an unreviewed guess. A bioinformatician has to sign
those nine lines off before a recipe may use them.

This is deliberate. The step-1 audit already learned that a generic "one string contains
the other" test produces false pairs (`SARS-CoV-2 Whole Genome Sequencing` vs
`Whole Genome Sequencing`), so no fuzzy matching is used anywhere here.

## What this says about decision D-a

| exit | verdict from the data |
|---|---|
| **1. the trigger also reads the SUSHI dataset** | **Works today.** 54.6% of raw datasets resolve to a reference (51.7% with no human input, +2.8% once the aliases are signed off), and it costs nothing: 13 of the 18 allow-listed apps declare `Species` in `required_columns`, so the execution layer has to read the dataset anyway. |
| 2. Species added to B-Fabric order metadata | This is the fix for the 39.2% gap, not an alternative to exit 1 — the value has to exist somewhere before either can read it. Target it at Ready-made Libraries Sequencing, which is 76.7% of the gap. It also lets a proposal be formed *before* data lands, and lets ordered vs delivered species be cross-checked. |
| 3. defer reference resolution to a later step | Does not unblock anything. `refBuild` is a required parameter for those same 13 apps, and unresolved `ref_selector` values reaching SLURM is exactly the bug the `required_params` gate was added to stop (design §5.2). A deferred `refBuild` cannot be pre-validated, so the proposal cannot be shown. |

## Running it

```bash
python3 species_audit.py                      # the classification table above
python3 species_audit.py --json out.json      # same, machine readable
python3 species_audit.py --resolve 'Mus musculus (house mouse)'   # reference_for() probe

/misc/ngseq12/miniforge3/envs/gi_py3.12.8/bin/python \
    crosscheck_order_service_type.py --pairs /tmp/omakase_order_species.tsv
```

`species_audit.py` needs only the standard library plus the reference catalog on disk.
`crosscheck_order_service_type.py` needs `bfabricPy` (present in `gi_py3.12.8`) and
`~/.bfabricpy.yml`; `--env` defaults to `PRODUCTION` for the same reason as the step-1
audit — the test instance answers nothing.

## Safety

* **Read-only.** `SELECT` only against the production SUSHI database, `read` only against
  B-Fabric. No writes, no DDL, and never `db:migrate` on 082.
* Every query ran under `SET SESSION max_statement_time` so it cannot pin the production
  server, and joined on the indexed `samples.data_set_id`.
* **No LLM.**
* **Aggregate output only.** Species names and service types are institutional controlled
  vocabulary and are printed; no project, order, sample or requester information is.
  The `order_id → species` intermediate stays in `/tmp` and is not committed.

## Re-taking the snapshots

Production database. Read-only, and get explicit go-ahead first.

```bash
ssh fgcz-h-082
set -a; . /etc/sushi/secret.env; set +a
export MYSQL_PWD="$SUSHI_DB_PASSWORD"
mysql --socket=/var/run/mysqld/mysqld.sock -u sushilover sushi --batch --raw <<'SQL'
SET SESSION max_statement_time=180;
-- species_snapshot_082_YYYYMMDD.tsv
SELECT species, COUNT(*) AS datasets, SUM(n_species > 1) AS mixed_species_datasets FROM (
  SELECT d.id,
         MAX(REGEXP_REPLACE(REGEXP_SUBSTR(s.key_value, '"Species[^"]*"=>"[^"]*"'),
                            '^"Species[^"]*"=>"|"$', '')) AS species,
         COUNT(DISTINCT REGEXP_REPLACE(REGEXP_SUBSTR(s.key_value, '"Species[^"]*"=>"[^"]*"'),
                            '^"Species[^"]*"=>"|"$', '')) AS n_species
  FROM data_sets d JOIN samples s ON s.data_set_id = d.id
  WHERE d.created_at >= '2025-08-21'
    AND (d.sushi_app_name IS NULL OR d.sushi_app_name = '')
    AND d.order_id IS NOT NULL
  GROUP BY d.id
) t GROUP BY species ORDER BY datasets DESC, species;
SQL
```

The `order_id → species` pairs for the cross-check use the same `FROM`/`WHERE` with
`SELECT d.order_id, MAX(...) GROUP BY d.id, d.order_id`.

`samples.key_value` is a Ruby `Hash#inspect` string (`{"Name"=>"x", "Species"=>"y"}`) —
see `backend/app/models/sample.rb`. The regex allows a tagged column name
(`"Species [Factor]"`), which is why it matches `"Species[^"]*"`.

## Snapshot files

| File | Content |
|---|---|
| `species_snapshot_082_20260821.tsv` | Species value → dataset count, mixed-species count |
| `service_type_crosstab_20260821.tsv` | service type → datasets, of which Species unusable |
