# Proposed `match:` updates for the recipe catalog (2026-10-02)

**For:** Paul Gueguen, author of the catalog (MR !1, `Internal_Dev/omakase/recipes/`).
**Status:** AI-drafted proposal (design decision D2), **not adopted**. Only you change your files.

## The problem

As written, the 12 recipes match **0 of 1467** real orders (measured 2026-09-24; question Q8
of `docs/omakase-recipe-format-v1/PROPOSAL.md`). Their `match` blocks use wording that
B-Fabric's order form never produces (`10x 3' Gene Expression`, `Illumina`, …).

## The proposal

`match_v2.yaml` (this directory) holds a replacement `match:` block per recipe. Nothing else
in your files changes. Every value is copied from B-Fabric PRODUCTION (orders created
2025-10-02 … 2026-10-02, `scripts/omakase_field_audit/`, mode `byapp`).

| Rule | Why |
|---|---|
| `sequencing_application`: B-Fabric's own value | The engine folds the `Single-Cell - ` / `Spatial - ` prefixes and the `Experssion` typo, so one value covers both wordings of each application |
| `instrument`: B-Fabric model names | The form records models (`Illumina NovaSeq X Plus`), not platforms (`Illumina`). Your platforms map to: Illumina → NovaSeq X Plus, NextSeq2000, MiSeq i100 #1; AVITI → Element Biosciences AVITI24; Xenium → 10X Genomics Xenium |
| `samples` removed | B-Fabric's `countsamples` counts every sample record (biological, library, pool, on-run, QC), a median 5.2× the biological samples over 25 orders. A `{min, max}` on it tests the wrong number |
| `library_protocol` / `library_protocol_option` added where they separate your variants | multiplexed or not; VDJ; CITE-seq; Visium v2 vs HD; BD WTA vs ATAC |
| `samples_contain_transgenes: false` added to the genome-derived recipes | An order declaring transgenes needs a reference the curated build lacks. Your call |

The engine gained the last two kinds of key on 2026-10-01: `library_protocol_option` passes
when **any** of the order's options is listed, and a yes/no key needs the order's exact answer
(no answer = no match).

## Measured effect (same 12 months, 1472 sequencing orders, order-level rules only)

| Recipe | Orders that would match | Main reason the others do not |
|---|---|---|
| spatial_xenium | 32 | — |
| sc_10x_3prime_gex | 40 | 24 multiplexed, 20 transgenes, 8 no instrument |
| spatial_visium_hd | 25 | 12 other Visium kits, 12 transgenes |
| sc_bd_rhapsody | 17 | 10 not WTA (6 are BD ATAC multiome) |
| sc_10x_multiplexed | 16 | |
| sc_10x_5prime_vdj | 15 | |
| sc_10x_citeseq | 10 | |
| sc_10x_flex | 10 | 10 transgenes / no answer |
| sc_parse_splitpipe | 8 | |
| spatial_visium | 5 | |
| sc_10x_multiome | 2 | wording not seen on ≥ 5 orders in 12 months; taken from older history |
| sc_10x_atac | 0 | no B-Fabric wording found; left unmatchable on purpose |
| **total** | **160 exactly one, 10 ambiguous (0.7%)** | was 0 |

The 10 ambiguous orders match two recipes at once, most likely CITE-seq together with 3′ or
5′/VDJ. The engine then abstains and a person chooses — safe, but if CITE-seq should win,
the format needs a "must not contain" rule. Your call.

Of the 32 orders currently at status `processed` on production, 4 would now get a proposal
(Flex 2, Parse 1, Visium HD 1).

## What this does not fix

- **Species wording — fixed in the engine 2026-10-02.** Production datasets mostly say
  `Mus musculus (house mouse)` (289 datasets). The engine now drops a trailing "(common name)"
  before comparing, also when it looks a Species up in your `species_aliases`, so your table
  needs no new entries for that form.
- **Runnable on the test backend today:** sc_10x_3prime_gex, sc_10x_multiplexed,
  sc_10x_5prime_vdj, sc_10x_flex (all their apps are among the 19 the backend submits). The
  others need BDRhapsodySA, SplitPipe, SpaceRanger, VisiumQC, Visium/Spatial Seurat, Xenium
  apps, CellRangerATAC/ARC or ScMultiOmics added to the backend's allow-list.

## Reproduce

```bash
cd scripts
COPY=$(python3 omakase_core/drafts/catalog_updates/apply_to_copy.py)   # temp copy, never your repo
OMAKASE_CATALOG_DIR=$COPY python -m omakase_match_audit.audit --source catalog
```
