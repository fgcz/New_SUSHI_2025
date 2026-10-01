# OMAKASE — which B-Fabric fields could help choose a recipe?

`match` reads four order fields today (service type, sequencing application, instrument,
library protocol) plus the sample count. This survey looks at **every** field of the order,
sample and project entities over the sequencing orders of the last 12 months on PRODUCTION.

```bash
P=/misc/ngseq12/miniforge3/envs/gi_py3.12.8/bin/python
cd scripts
$P -m omakase_field_audit.field_audit inventory                 # every order field, no values
$P -m omakase_field_audit.field_audit values instrumentreadconfiguration libraryprotocoloption
$P -m omakase_field_audit.field_audit crosstab instrumentreadconfiguration
$P -m omakase_field_audit.field_audit samplefields --orders 120 # sample drop-downs per order
$P -m omakase_field_audit.field_audit keywords remarks          # keyword COUNTS, never text
$P -m omakase_field_audit.field_audit projectkeywords
$P -m omakase_field_audit.field_audit projects --orders 300
$P -m omakase_field_audit.field_audit nameshape name
```

## Safety

Order records are FGCZ `internal`, and project descriptions may be unpublished research.

* Read-only (`read` only). No LLM. Nothing cached to disk.
* `inventory`, `samples`, `projects` print field names, types and counts — no values.
* `values` / `crosstab` / `samplefields` print a value only if it occurs on at least 5
  orders (`--min-count` cannot go lower), and refuse fields that name people or carry
  free text (`NEVER_PRINT`).
* Free text (`remarks`, project `summary`) is only ever **counted** against fixed keyword
  families; `nameshape` prints the letter/digit shape, not the text.

## Result, 2026-10-01 (PRODUCTION, orders created after 2025-10-01)

1472 sequencing orders. **749 (51%) are in the gap**: their service type plus sequencing
application cannot pick a recipe. The gap is 514 Ready-made Libraries Sequencing (RML),
192 Bench Access, 23 Genome Informatics, 10 NGS, 10 other — so the analysis-relevant gap
is the **514 RML orders**.

The order endpoint returns **101 fields** (not 49: B-Fabric omits empty fields, so one
record shows only what it has). Most are billing or people. The useful ones:

| Field | Filled (1472) | Filled in the gap (749) | What it carries |
|---|---|---|---|
| `libraryprotocol` | 49.8% | **1.3%** (10, all `Custom`; RML 0 of 514) | kit/chemistry: `Tecan Universal Plus mRNA-Seq`, `GEM-X (v4)`, `Visium HD (probe-based)` … |
| `libraryprotocoloption` | 18.1% | 0% | `Human/Mouse Probe Set v2`, `FFPE`/`FF`, `TCR`/`BCR`, `Cell Hashing`, `Cell Surface Protein`, `On-Chip Multiplexing` |
| `instrumentreadconfiguration` | 71.8% | 68.6% (RML 508 of 514) | `Paired End 150 bp`, `10x Universal Paired End (28_91 bp)`, `BD …`, `Parse WT …`, `Visium HD …`; in the RML gap mostly `Paired End 150 bp` or `Custom` |
| `samplescontaintransgenes` | 68.3% | 57.9% (RML: 25 True, 403 False) | the standard genome is not enough |
| `nuclei` | 5.7% | 0% | nuclei, not cells (CellRanger `includeIntrons`) |
| `storagemodel` | 84.7% | 70.0% | `Bioinformatics Analysis and Support` 231 vs `Data Delivery Only` 1016 |
| `remarks` (free text) | 63.2% | 61.3% | an assay keyword on only 11.6% of gap orders |
| `name` | 100% | | generated: "word word date" on 1054 orders — a person's name and a date. Useless and personal |

Sample entity (58 fields; 120 sampled orders per group):

| | RML gap | RML outside gap | analysis service types |
|---|---|---|---|
| `species` on at least one sample | **44.2%** (16 of 53 are `n/a`) | 60.8% | 72.5% (17 `n/a`) |
| `type` | `Library …` only | `Library …` only | also `Biological Sample - Single Cell / Spatial VIS / Sequencing` |
| `multiplexkit` / `samplepreparationprotocol` / `sourcetype` | 0% | 0–15% | 42–45% (`10X_TT_Dual_Index`, `Total RNA`, kit names) |

**Correction:** the 2026-08-20 audit said Species does not exist in B-Fabric. It exists on
the **sample** entity (`species`, an annotation reference); that probe saw a record without
it.

Project entity: `summary` (research description) is filled on 100%, median 667 characters.
An assay keyword appears for 52.5% of RML gap orders (79 of 140 projects) and 64.3% of
analysis orders. It describes the project, not this order, so it is a hint, not a rule —
and reading it needs the on-prem model.

**Reading:** outside the gap, `libraryprotocol`, `libraryprotocoloption`,
`instrumentreadconfiguration`, `nuclei` and `samplescontaintransgenes` can sharpen a choice
(assay variant, parameters, and when to abstain). **Inside the RML gap no structured field
names the assay**; only sample `species` (~30% real values), the read layout, and free
text remain.
