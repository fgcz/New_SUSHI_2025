# Review guide — AI-drafted OMAKASE recipes (2026-10-01, extended 2026-10-02)

**For:** a bioinformatician deciding whether OMAKASE may use these recipes.
**Status:** AI drafts, **not adopted**. Nothing here runs on production until you adopt it.

## What you are asked to decide

OMAKASE proposes an analysis chain for a finished sequencing order, a person approves it, and
the engine runs it. *Which* chain is decided by recipes. Since 2026-10-01 (design decision D2)
an AI may **draft** a recipe, and **a bioinformatician decides whether it is adopted and is
accountable for it**. The files in this directory are such drafts:

| Draft | Part of this guide | Runnable on the test backend today |
|---|---|---|
| `bulk_rnaseq_stranded_antisense`, `bulk_rnaseq_stranded_sense`, `bulk_rnaseq_unstranded` | Bulk RNA-seq (below) | yes |
| `dna_wgs_alignment` | DNA: whole-genome alignment | yes |
| `methylation_wgbs_bismark` | Methylation: WGBS / EM-seq | **no** — BismarkApp is not on the backend's allow-list |

`catalog_updates/` is a separate proposal for the existing catalog's `match` blocks, written for
its author (see its README).

For each draft, one of:

| Answer | What happens |
|---|---|
| Adopt | It moves into the recipe catalog with your name as the adopter; OMAKASE may then select it |
| Adopt with changes | Edit the file (or say what to change); the changed version is what gets adopted |
| Reject | It stays out; say why, so the next draft does not repeat it |

How the engine treats a draft until then (enforced in code, tested):
`omakase match` reports when a draft *would* match, automatic selection **never** picks one,
and a person can run one by name **only on the test instance** (fgcz-h-083).

## Bulk RNA-seq: the three drafts

All three run the same five steps; only the strand setting and the kits they accept differ.

```
fastqc        ┐
fastqscreen   ┤ start together
star          ┘ ──▶ featurecounts ──▶ countqc
```

| Draft | Accepts orders whose Library Protocol is | strandMode | Orders, last 12 months |
|---|---|---|---|
| `bulk_rnaseq_stranded_antisense` | Illumina Stranded mRNA Prep, Ligation; Illumina Stranded Total RNA Prep, Ligation with Ribo-Zero Plus | `antisense` | 44 + 10 = 54 |
| `bulk_rnaseq_stranded_sense` | Tecan Universal Plus mRNA-Seq; Tecan Universal Plus Total RNA-Seq | `sense` | 67 + 14 = 81 |
| `bulk_rnaseq_unstranded` | Smartseq II | `both` | 17 |

Every draft also requires Sequencing Application = "Transcriptome Sequencing", the order to
state that the samples contain **no** transgenes, and the dataset's Species to have a curated
genome in `/srv/GT/reference-favorite`.

### Where each strand setting comes from

In ezRun, `strandMode` maps to featureCounts `strandSpecific`: `both` = 0, `sense` = 1,
`antisense` = 2 (`ezRun/R/app-featureCounts.R`, lines 84–90).

| Kit family | Read 1 is | Source |
|---|---|---|
| Illumina Stranded / TruSeq Stranded (dUTP) | antisense | Illumina knowledge base, "Which reads map to each strand in Stranded RNA workflows": <https://knowledge.illumina.com/library-preparation/rna-library-prep/library-preparation-rna-library-prep-reference_material-list/000002238> |
| Tecan Universal Plus mRNA-Seq / Total RNA-Seq | **sense** | Tecan user guide M01523: "the forward read … represents the sense strand", with a warning that this differs from other kits: <https://www.tecan.com/hubfs/HubDB/Te-DocList/UG_Universal_Plus_Total_RNA-Seq_with_NuQuant_M01523.pdf> |
| Smart-seq2 | no strand information | The method's published design (Picelli et al., Nat Protoc 2014, <https://doi.org/10.1038/nprot.2014.006>); not a vendor statement |

Tecan lists Universal Plus mRNA-Seq with NuQuant as **phased out** (April / July 2026), yet 67
FGCZ orders named it in the last 12 months.

### What the data decides, not the recipe

- **Genome (`refBuild`)**: derived from the input dataset's `Species` column through the
  curated build per species. No Species, two species, or an uncurated species → the order is
  refused, never guessed.
- **`paired`**: left out on purpose. The backend applies each app's defaults first, and STAR and
  FastQC set `paired` from whether the dataset has a `Read2` column. FeatureCounts then takes
  `paired` and `strandMode` from STAR's output dataset.
- **Resources**: each app's shipped defaults (STAR 8 cores / 30 GB, one automatic retry at
  60 GB after an out-of-memory failure).

## Bulk RNA-seq: what was measured (B-Fabric PRODUCTION, orders created 2025-10-01 … 2026-10-01)

Read-only, counts only; no order text or sample data was read.

| | Orders |
|---|---|
| Sequencing orders | 1473 |
| … with Sequencing Application "Transcriptome Sequencing" (all of them NGS service) | 199 |
| … whose Library Protocol is one of the five kits above | 152 |
| … that also state "no transgenes" → **one draft matches, none is ambiguous** | **100** |
| held back: samples contain transgenes | 23 |
| held back: the order does not answer the transgenes question | 29 |

The other 47 of the 199 are left to a person on purpose: "I do not know" (15), Takara
SMART-Seq Pico kits (17; UMI and trimming need a decision), and the two "Illumina Truseq …"
entries (13; the names do not say "Stranded").

## Bulk RNA-seq: one run on the test instance (fgcz-h-083, 2026-10-01)

`bulk_rnaseq_stranded_antisense` on dataset 9 (mouse, 2 samples, 100 000 reads each; its library
kit is not recorded), approved by a person, run by the engine:

| Step | Result |
|---|---|
| FastQC, STAR, featureCounts | COMPLETED; genome derived as GRCm39 (GENCODE M37); STAR 4 min, featureCounts 3 min after it |
| featureCounts with `antisense` | **22 184** reads assigned per sample |
| the same data with `both` (2026-09-15 run) | **42 752** assigned |
| CountQC | FAILED inside its Quarto report, the same error as on 2026-09-11 → chain halted, as designed |

Reading it: `antisense` keeps 52% of what `both` assigns. A correctly stranded setting keeps
nearly all of it, a wrong one nearly none, so **this test library looks unstranded** — the
parameter reaches featureCounts and visibly matters, which is the point of the per-kit split.
It says nothing about whether the antisense draft is right for Illumina Stranded kits.

On CountQC: dataset 9's two samples give **byte-identical** counts. The failure may come from
zero variance between samples rather than from there being two. It cannot be told apart here.

## Bulk RNA-seq: open questions

| # | Question | Draft(s) |
|---|---|---|
| Q1 | Illumina recommends trimming the first base of each read for Stranded mRNA (an added T gives a low-diversity first cycle). STARApp offers `trim_front1` (fastp); the drafts leave the default 0. Set it to 1? | antisense |
| Q2 | Are FGCZ's "Illumina Truseq mRNA" (7) and "Illumina Truseq Total RNA (ribosomal depletion)" (6) the **stranded** TruSeq kits? If so they belong in the antisense draft. | antisense |
| Q3 | Total RNA (ribo-depleted) and mRNA libraries share one chain. Should QC expectations differ (intronic fraction)? | antisense, sense |
| Q4 | Does FGCZ's Tecan protocol need read trimming? And what replaces the phased-out kit? | sense |
| Q5 | Is a Smart-seq2 order at FGCZ bulk, or plate-based single-cell (one cell per sample)? The draft assumes bulk. | unstranded |
| Q-samples | CountQC failed inside its report on a 2-sample dataset (2026-09-11) and has no sample-count guard. The order cannot tell the true sample count: B-Fabric's `countsamples` counts every sample record (biological, library, pool, on-run, QC), a median 5.2× the biological samples over 25 orders. So a 1–2 sample order would reach CountQC and halt there. Keep CountQC? | all |
| Q-resources | Is 30 GB enough for STAR on FGCZ's GRCh38 / GRCm39 indexes, with 60 GB as the retry? | all |
| Q-DE | No differential-expression step: the control-versus-treatment grouping is a judgement nothing here can make. Agreed? | all |

## DNA: `dna_wgs_alignment`

FastQC, FastQ Screen and BWA-MEM side by side, then DnaBamStats. **No variant calling.**

- **Orders:** "Whole Genome Sequencing", 44 in 12 months, all NGS service; 31 pass the order-level
  rules (13 held back by transgenes: 5 yes, 8 no answer).
- **Why it stops at alignment QC:** in the SUSHI execution history, 17 of 36 WGS orders got QC
  only and the rest split by purpose — BWA 22%, DnaBamStats 25%, Kraken (metagenomics) 13%,
  Mutect2 (somatic) 8%, GATK germline 5%. The order does not say which purpose, so the common
  part is drafted and the rest left to a person.
- **Why three species:** BWAApp builds a missing BWA index inside the shared reference tree
  (hours). The index exists for Homo sapiens (GRCh38.p14), Mus musculus (GRCm39) and
  Arabidopsis thaliana (TAIR10), not for dog or rat.
- **Questions:** which variant caller, if any (GATK is not submittable; Mpileup is)? Is
  200 GB scratch enough for a 30× human genome per sample?

## Methylation: `methylation_wgbs_bismark`

FastQC, FastQ Screen and Bismark (Bowtie2) side by side. Not runnable until BismarkApp is
added to the backend's allow-list — drafted so that decision and this review happen together.

- **Orders:** "Whole Genome Bisulfite Sequencing", 8 in 12 months; kit "NEB Enzymatic Methyl
  Seq v2" on 6, which is the rule. Bismark ran on 63% of 11 WGBS orders in the history — the
  most consistent DNA application.
- **Why the kit is a rule:** EM-seq is directional, Bismark's default; BismarkApp has no
  directionality switch, so a PBAT / non-directional kit must not reach this recipe.
- **Why two species:** the Bisulfite_Genome index exists for human and mouse only.
- **Questions:** turn on `EM_QC` (lambda / pUC19 controls)? extra trimming for EM-seq?
  `deduplicate=true` (default) — confirm no amplicon bisulfite kit can match.

## Not drafted, on purpose

| Application | Orders | Why no draft |
|---|---|---|
| CRISPR Screen / Readout | 22 / 11 | MageckCountApp needs `libName`, the screen's sgRNA library, picked from a list. Nothing in the order says which library (kit = "Custom Primers" on all 22). A recipe would have to guess it |
| SARS-CoV-2 WGS, Amplicon, Small RNA | 27 / 26 / 12 | The history shows QC only on nearly all of them (25/26, 4/5, 6/10). Small RNA ran as an nf-core pipeline on 2 orders, which the backend cannot submit |
| Long read (de novo, isoform, metagenomics on ONT/PacBio) | 31 / 17 / 18 | No long-read app among the 19 the backend submits |

## Species wording (fixed 2026-10-02)

The genome is derived from the dataset's `Species` column. Production datasets mostly carry
B-Fabric's annotation names — `Mus musculus (house mouse)` on 289 datasets against 17 bare
`Mus musculus`. Until 2026-10-02 the resolver refused those. It now drops a trailing
"(common name)" and maps five names (`Human`, `Mouse`, `Rat`, `Dog`, `Canis lupus
familiaris`) to the Latin names the curated farm is keyed by; which build each species gets
is unchanged. Measured on the 082 snapshot (1376 datasets): **28.8% → 53.9%** resolve. The
rest is blank / NA (39.2%) or a species with no curated build — still refused.

## Where things are

- The drafts: `scripts/omakase_core/drafts/*.yaml`. Each file repeats its own reasoning in comments.
- The measurement: `scripts/omakase_field_audit/` (which fields exist and how often they are
  filled) and `python -m omakase_match_audit.audit --source draft` (how many orders each draft
  matches).
- The rule that a draft is never selected automatically: `scripts/omakase_core/recipes.py`
  (`select`, `check_draft_allowed`), tested in `test_match.py`.
