# B-Fabric order metadata — what OMAKASE needs, with the numbers

**Draft for review. Not sent.**
Owner of the change: Simon (B-Fabric order metadata). Requested by: Genome Informatics.
Evidence: read-only audits of production B-Fabric and the production SUSHI database,
2026-08-21. Window: orders created after 2025-08-21.

This replaces the earlier informal request ("Custom/Other for ready-made library
sequencing is useless") with a measured one. The short version: **the request is much
smaller than it looked. One service type carries the entire gap.**

---

## 1. Why we are asking

`docs/omakase-auto-analysis-design.md` proposes that when sequencing for an order
finishes, a rule — not a language model — selects a first-pass analysis, a
bioinformatician approves it, and it runs through the existing SUSHI job path. The rule is
a deterministic predicate over a handful of order fields. It can only be as good as those
fields.

We measured how many real orders that predicate could decide today.

| | orders | share |
|---|---:|---:|
| all orders in the window | 2982 | |
| of those, sequencing orders (`technology` contains `Genomics`) | 1467 | 100% |
| **sequencing orders where every required field is usable** | **722** | **49.2%** |

"Required" means Service Type plus Sequencing Application, present and not the menu entry
`Custom / Other`. Service Type is filled on 100% of orders, so Sequencing Application is
the whole story:

| Sequencing Application | orders | share |
|---|---:|---:|
| usable | 722 | 49.2% |
| `Custom / Other` | 513 | 35.0% |
| empty | 232 | 15.8% |

---

## 2. The gap is one service type

| service type | orders | decidable today |
|---|---:|---:|
| **Ready-made Libraries Sequencing** | **651** | **22.7%** |
| High Throughput Sequencing (NGS) | 315 | 96.8% |
| Genomics User Lab — Bench Access | 188 | 0% |
| Single Cell Sequencing | 84 | 100% |
| Spatial Gene Expression | 68 | 100% |
| Long Read Sequencing | 68 | 100% |
| ONT Ready-Made Libraries Sequencing | 38 | 100% |
| Genome Informatics | 31 | 0% |
| CRISPR Screen | 11 | 100% |

Two readings matter:

* The service types that deliver sequencing data for analysis are **already ready** —
  584 orders at 98.3% (574 decidable). Nothing needs to change for them.
* **Bench Access (188) and Genome Informatics (31) read 0% but are not analysis targets.**
  In Bench Access the customer does the bench work; Genome Informatics *is* the
  bioinformatics service. We are not asking for anything there.

That leaves one service type. Where its required field fails:

| service type | Sequencing Application vague or empty |
|---|---:|
| Ready-made Libraries Sequencing | **503 / 651 = 77.3%** |
| High Throughput Sequencing (NGS) | 10 / 315 = 3.2% |

---

## 3. Three requests

### R1 — Sequencing Application, for Ready-made Libraries Sequencing only

Make it mandatory, and remove `Custom / Other` as an acceptable answer **for this service
type**. The customer prepared the library, so the customer knows what it is.

**Buys:** 503 orders per year become decidable. Sequencing orders go from 49.2% to roughly
83%. Nothing else in the survey moves the number materially.

### R2 — Species, as a new order field

Species does not exist in order metadata at all. We probed production: the order endpoint
returns 49 fields and the sample endpoint 13, and none of them is species, organism, taxon
or strain.

This matters because the reference genome is chosen from the species, and every
alignment-based analysis needs it. Today the value only appears later, as a column on the
SUSHI dataset, where it is filled in by hand:

| Species on delivered SUSHI datasets (1376 datasets from 974 orders) | datasets | share |
|---|---:|---:|
| a specific species | 836 | 60.8% |
| **`NA`, `n/a`, `Unidentified` or blank** | **540** | **39.2%** |

And the same service type carries that gap too:

| service type | delivered datasets | Species unusable | share |
|---|---:|---:|---:|
| **Ready-made Libraries Sequencing** | 714 | **414** | 58.0% |
| High Throughput Sequencing (NGS) | 440 | 100 | 22.7% |
| Single Cell Sequencing | 99 | 4 | 4.0% |
| Spatial Gene Expression | 60 | 5 | 8.3% |

**Ready-made Libraries Sequencing is 76.7% of every unusable Species value.** So R1 and R2
are one change to one form, not two separate projects.

**Buys:** a proposal can be formed when the order is placed rather than after data lands,
and the species the customer ordered can be checked against the species in the delivered
dataset. It also removes hand-entry: 4 different spellings of human and 3 of mouse are in
use today (see R3 — the same problem, one level down).

A controlled list would be better than free text. Five species — human, mouse, rat, dog,
*Arabidopsis thaliana* — account for 85% of everything we can already resolve.

### R3 — Five duplicate entries in the Sequencing Application menu

A recipe matches these strings exactly. Two spellings of one application means either two
rules to keep in sync, or one rule that silently misses half the orders.

| orders | the two entries | issue |
|---:|---|---|
| 92 | `Single-Cell - 10x Genomics - Universal 3' Gene Expression` / `10x Genomics - Universal 3' Gene Expression` | category prefix only |
| 50 | `10x Genomics Visium` / `Spatial - 10x Genomics - Visium` | category prefix only |
| 31 | `Single-Cell - BD Rhapsody` / `BD Rhapsody` | category prefix only |
| 29 | `Single-Cell - 10x Genomics - Universal 5' Gene Expression` / `10x Genomics - Universal 5' Gene Expression` | category prefix only |
| 22 | `Single-Cell - 10x Genomics - Flex Gene Expression` / `10x Genomics - Flex Gene Experssion` | **misspelling**: `Experssion` |

The last row is the one to fix first. It is a typo in a menu entry, so 11 orders are filed
under a value no rule would ever be written for.

**Buys:** 224 orders stop being ambiguous. This one costs nothing but a vocabulary edit.

---

## 4. What we do on our side regardless

We are not waiting on these changes.

| Our side | What |
|---|---|
| Spelling drift | The recipe predicate normalises before matching, so both spellings of a pair resolve to one rule. This is a workaround, not a fix — every new spelling needs a code change. |
| Species | The trigger reads the delivered SUSHI dataset, which is where the value lives today. 54.6% of delivered datasets resolve to a reference genome with no human input. |
| Reference genome | Taken from `/srv/GT/reference-favorite`, the curated recommended build per species that the reference owners already maintain. We do not invent a species-to-build policy. |
| Start order | Recipes are written first for the service types already near 100% — NGS, Single Cell, Spatial, Long Read, ONT. Ready-made Libraries waits on R1 and R2. |

---

## 5. How this was measured

Two scripts in the SUSHI repository, both read-only, both without any language model, and
both printing counts only — no order labels, project names, requester names or sample
names:

| Script | Reads |
|---|---|
| `scripts/omakase_metadata_audit/audit.py` | B-Fabric orders (`read` only) |
| `scripts/omakase_species_audit/species_audit.py` | a species snapshot of the SUSHI database (`SELECT` only) + the reference catalog on disk |
| `scripts/omakase_species_audit/crosscheck_order_service_type.py` | joins the two, by order |

Each script's README records the exact query and how to re-take the snapshot. Numbers in
this document were re-taken on 2026-08-21 and will drift slightly as the 12-month window
moves.
