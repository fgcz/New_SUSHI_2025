# OMAKASE step 1 — metadata-readiness audit

Implements step 1 of `docs/omakase-auto-analysis-design.md` §17.

It answers one question: **for how many real orders could a recipe be selected
from B-Fabric order metadata alone today?** That number decides whether OMAKASE
is worth building, so the script only counts — it does not interpret, and it
never calls an LLM.

## Running it

```bash
/misc/ngseq12/miniforge3/envs/gi_py3.12.8/bin/python audit.py --months 12
/misc/ngseq12/miniforge3/envs/gi_py3.12.8/bin/python audit.py --months 3 --json out.json
/misc/ngseq12/miniforge3/envs/gi_py3.12.8/bin/python audit.py --env TEST     # smoke test
```

Needs `bfabricPy` (present in `gi_py3.12.8`) and `~/.bfabricpy.yml`.

**`--env` defaults to `PRODUCTION` on purpose.** The `default_config` in
`~/.bfabricpy.yml` is `TEST`, and auditing the test instance would answer a
question nobody asked.

## Safety

* **Read-only by construction.** The only B-Fabric call used is `read`. Nothing
  is written to B-Fabric, gStore, or the SUSHI database.
* **No LLM.** Order metadata is FGCZ `internal`; not sending it to a model at
  all is simpler than arguing about which model is permitted.
* **Aggregate output only.** Order labels, project names, requester names and
  sample names are never printed. Service types and sequencing applications
  are controlled vocabulary, so those values are printed.

## Field mapping

The L0 allow-list in design §3.1 uses human labels. These are the field names
the order endpoint actually returns, verified against production 2026-08-20:

| Design label | API field |
|---|---|
| Service Type | `servicetype` (dict, id resolved via the `servicetype` endpoint) |
| Sequencing Application | `sequencingapplication` |
| Instrument | `instrument` |
| Library Protocol | `libraryprotocol` |
| sample count | `numberofsamples` (declared) and `countsamples` (derived) |
| **Species** | **does not exist** — see below |

Each field is classified `present` / `vague` / `empty`. `vague` means a value
that looks filled to any completeness check but carries no decision content —
in practice the literal menu entry `Custom / Other`.

## What it found (production, 12 months to 2026-08-20)

2981 orders total; 1463 carry the `Genomics` technology.

**Sequencing orders: 49.3% (721/1463) have both required fields usable.**

The gap is concentrated in one service type:

| Service type | orders | usable |
|---|---|---|
| Ready-made Libraries Sequencing | 648 | **22.8%** |
| High Throughput Sequencing (NGS) | 313 | 96.8% |
| Single Cell Sequencing | 85 | 100% |
| Spatial Gene Expression | 68 | 100% |
| Long Read Sequencing | 68 | 100% |
| ONT Ready-Made Libraries Sequencing | 38 | 100% |
| CRISPR Screen | 11 | 100% |
| Genomics User Lab — Bench Access | 188 | 0% |
| Genome Informatics | 31 | 0% |

Reading that table:

* The service types that deliver sequencing data for analysis are **already
  ready** — 583 orders, 573 of them usable (98.3%).
* **Ready-made Libraries Sequencing is the whole problem.** It is the largest
  single type, and 500 of its 648 orders (77%) have `Custom / Other` or an
  empty Sequencing Application. This is the quantified version of the request
  already made to Simon.
* Bench Access and Genome Informatics are 0% but are **not** analysis targets:
  the customer runs the bench work themselves, and Genome Informatics *is* the
  bioinformatics service. Excluding those and the administrative types leaves
  1231 orders at 58.6% — and fixing the one field on the one service type would
  take it to roughly 99%.

Secondary findings:

* `Instrument` is present on 80.3% of sequencing orders — better than expected.
* `Library Protocol` is present on only 47.8%.
* Declared sample count 70.9%; derived count 81.1%. Prefer the derived one.

## Two findings that change the design

### 1. Species is not available at order level

Probed against production: the order endpoint returns 49 fields, the sample
endpoint 13, and **none** matches species / organism / taxon / strain. In SUSHI,
`Species` is a dataset **column** — many legacy apps list it in
`required_columns` — so it only exists once a dataset does.

Design §3.1 puts Species on the allow-list and §5 has the recipe resolve a
reference genome from it. Neither is possible from the order alone. Taken
literally, the addressable share is **0%**, not 49.3%; the 49.3% figure is what
you get after dropping Species from the requirement. Three ways out, all needing
a decision:

1. the trigger also reads the SUSHI dataset (which is what v0.2 proposed and
   v0.3 dropped);
2. Species is added to B-Fabric order metadata (fold into the Simon request);
3. recipes defer reference resolution to a later step.

### 2. The vocabulary itself has duplicate entries

A recipe match predicate keys off these strings, so two spellings of one
application are two recipes to keep in sync — or one that silently fails to
match. Found in the last 12 months:

| orders | issue |
|---|---|
| 92 | `Single-Cell - 10x Genomics - Universal 3' Gene Expression` vs `10x Genomics - Universal 3' Gene Expression` |
| 50 | `10x Genomics Visium` vs `Spatial - 10x Genomics - Visium` |
| 32 | `Single-Cell - BD Rhapsody` vs `BD Rhapsody` |
| 29 | the same 5' pair as the 3' one above |
| 22 | **spelling**: `Flex Gene Expression` vs `Flex Gene Experssion` |

The detector reports only two narrow signals — a difference consisting purely of
a category prefix, and a single near-identical token. A generic "is one string
contained in the other" test was tried first and rejected: it also paired
`SARS-CoV-2 Whole Genome Sequencing` with `Whole Genome Sequencing`, which are
different services.

## Next

Design §17 steps 2 and 3: recipes for the top order types, written by
bioinformaticians; then shadow mode on new orders. Step 2 should start with the
service types that are already at ~100%, not with Ready-made Libraries.
