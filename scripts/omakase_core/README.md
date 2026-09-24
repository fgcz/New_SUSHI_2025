# omakase_core — the prototype's first vertical slice

Implements `docs/omakase-auto-analysis-design.md` v0.3 as amended by
`docs/omakase-prototype-design-delta.md`:

```
order event  ->  candidate  ->  [FIXED recipe]  ->  proposal  ->  human approves
             ->  chain runner, one step at a time  ->  DONE or CHAIN_HALTED
```

The order event comes from `scripts/omakase_order_watch/`, which notices when a B-Fabric
order reaches `status=processed`.

**No model is involved anywhere in this package.** Design decision D4 keeps the trigger,
the timer, every state transition and the retry decision in ordinary code, so the order in
which things happen cannot depend on a model's judgement.

## Why the chain is stepped

`job_manager` hardcodes `afterany` (`scheduler.py:65`) and, when a parent has *already*
failed, attaches no dependency at all (case 7 of
`scripts/job_manager_contract/wait_branch_check.py`). **SLURM will start a child whose
parent failed.** So the runner submits step N+1 only after step N reports `COMPLETED`, and
nothing here relies on SLURM to stop a chain.

`COMPLETED` is the literal. There is no `SUCCESS` state on this system.

## Use

```bash
cd scripts
python3 -m omakase_core.omakase recipes
python3 -m omakase_core.omakase ingest  --event ~/.omakase/test/fixtures/order_35755_chain_fixture.json
python3 -m omakase_core.omakase show    --candidate 1
python3 -m omakase_core.omakase approve --candidate 1 --actor <you>
python3 -m omakase_core.omakase run     --candidate 1 --dry-run
python3 -m omakase_core.omakase run     --candidate 1
```

`--dataset` is **optional since 2026-09-11**. Left out, the order is resolved to the one
parentless dataset in its project carrying that order id — see below. Given, it wins, which
is not only a fallback: when an order resolves to several raw datasets, which one to
analyse is genuinely a person's call.

Approval is explicit and human every time; the deadline-driven auto-approval of v0.3 §10 is
deliberately absent.

## order → dataset, and why the key is what it is

The link is not held by B-Fabric. `data_sets.order_id` is derived inside SUSHI from the
dataset's own `Order Id [B-Fabric]` sample column, and only when every sample agrees on one
order (`backend/app/models/data_set.rb:58-77`).

Measured on project 35611, all 82 datasets opened in 2.6 s:

| population | count | |
|---|---|---|
| datasets in the project | 82 | one list call; the summary does **not** carry `order_id` |
| carrying the **column** for order 35755 | 62 | every descendant of dataset 9 inherits it |
| carrying the scalar **`order_id`** | 3 | 9, 559, 682 |
| of those, **parentless** | **1** | dataset 9 — the raw delivered data |

Both halves of the key matter. Match the column instead and you get 62 candidates; drop the
parent test and you get 3, two of which are themselves analysis output — and analysing an
analysis is exactly the wrong answer.

Opening only the parentless datasets is also what makes it cheap: 7 detail calls here, not
82, at ~53 KB and ~29 ms each. There is no server-side filter — `?order_id=` is silently
ignored — though the column *is* indexed (`schema.rb:50`), so adding one is small if it ever
needs to scale.

**Refusing is the common case, not an error.** An order that has just reached `processed`
usually has no registered dataset yet. That prints `DECLINED: …` and exits **3**, so a
caller can tell "declined" from "failed" (2).

Store defaults to `~/.omakase/<profile>/omakase.sqlite3` — `--profile test` (the default: B-Fabric TEST + the fgcz-h-083 backend) or `--profile production` (B-Fabric PRODUCTION + fgcz-h-082, read only: `run` is DECLINED). `ingest` DECLINES an event whose `env` is missing or belongs to the other instance. See `profile.py`. Tables are v0.3 §12 — `candidates`,
`order_params`, `proposal_steps`, `transitions`, `submissions` — with two additions the
stepped runner needs: `submissions.state/attempt/finished_at`, and
`proposal_steps.retry_params_json`.

## Two app lists, and only one of them can be submitted

This cost a live 422 to discover and is the trap most likely to bite the next person.

| | |
|---|---|
| `GET /api/v1/datasets/:id` | every app the legacy catalogue thinks is **column-compatible** — 175 for dataset 9 |
| `GET /api/v1/application_configs` | the **18** this backend will actually run: one native (`Fastqc`) plus the 17 in `config.legacy_apps_allowlist` |

`FlashApp` is in the first list and not the second, which is why
`recipes/flash_then_fastqc.yaml` is disabled rather than deleted — it is the regression
case in prose. The runner checks the second list before submitting and halts with a reason.

The chain the 2026-09-10 meeting asked for is entirely inside the submittable 18: **STAR,
FeatureCounts, CountQC, EdgeR.** See `recipes/star_then_featurecounts.yaml`.

## The genome is derived, and the refusals are the feature

The meeting named two judgements the system must make on its own. The first —
*STARApp's reference genome, from the metadata rather than typed in* — is implemented in
`reference.py`, and there was nothing to invent:

```
dataset's Species column   ->   /srv/GT/reference-favorite   ->   refBuild
   "Mus musculus"                5 species, 1 build each          Mus_musculus/GENCODE/
                                 curated by the genome team       GRCm39/Annotation/
                                 (the same list SUSHI's own       Release_M37-2025-07-03
                                  refBuild dropdown shows first)
```

A recipe writes `refBuild: FROM_SPECIES`; the engine expands it **at proposal time**, so
the human approving sees the real path, not the sentinel. Approving a placeholder would
make the approval meaningless.

Four cases are refused rather than defaulted, and they are not rare: **39.2 %** of
delivered datasets carry `NA` / blank Species and **5.7 %** carry more than one (measured
2026-08-21 over 1376 raw datasets). A species outside the curated five is a request to the
genome team, not a path this code may construct. A wrong genome is worse than a refused
submission — STAR will align mouse reads to a plant genome and hand back a directory of
near-zero counts, which looks like data.

Step 2 sets no `refBuild` and that is deliberate. STAR's output dataset carries the columns
`Species`, `refBuild`, `paired` and `strandMode`, and `FeatureCountsApp.rb:59` reads
`refBuild` off its input dataset unconditionally. The genome is decided once and travels
**through the data**, so there is no second copy to drift.

The second judgement — EdgeR's control-vs-target grouping — is still open and deliberately
absent. The `match:` block is still `TODO`, so `select()` never reaches this recipe on its
own; it runs only when named with `--recipe star_then_featurecounts`. That still needs a
bioinformatician.

## Retry

Provisional compromise agreed 2026-09-10, amending v0.3 §11's flat "no auto-retry":

* transient **by SLURM's own report** only — `OUT_OF_MEMORY`, `TIMEOUT`, `NODE_FAIL`,
  `PREEMPTED`. Never by reading logs. Unknown counts as not transient.
* **one** retry per step; a second failure halts the chain whatever the reason.
* the retry must **ask for more**, or an out-of-memory job repeats identically. The recipe
  states the larger values, because several apps declare `ram` as a selector — FastqcApp
  offers `[15, 30, 62]`, so doubling 30 would ask for 60, which is not on offer.
* every retry is written to `transitions` and shown to the human. Never silent.

Grounding: of 30 118 SLURM end states since 2026-09-01, 82 were `OUT_OF_MEMORY` and 5
`TIMEOUT` — 0.29 % of all jobs, 3.8 % of the 2 280 that did not complete. Real, but rare.

## Tests

```bash
python3 omakase_core/test_runner.py         # rc 0 = the runner behaves as the delta says
python3 omakase_core/test_reference.py      # rc 0 = the genome refusals still refuse
python3 omakase_core/test_input_dataset.py  # rc 0 = order -> dataset still refuses
python3 omakase_core/test_gate.py           # rc 0 = the pre-registered gate is untouched
```

Six cases against a fake backend, because the one that matters cannot be produced on demand
against a cluster: **a step fails for a non-transient reason and the next step is never
submitted.** That is what `afterany` gets wrong, and it is why the runner exists.

Both halves are now also proven **live** (2026-09-11, fgcz-h-083): candidate 1 ran
STAR → FeatureCounts to `DONE`, and candidate 2 — `recipes/acceptance_halt_fixture.yaml`,
aimed at a genome that does not exist — halted with step 2 never submitted. Details in
`docs/omakase-prototype-design-delta.md` §F.

`test_reference.py` is 17 cases against a fixture farm, and most of them are refusals. The
happy path is a dictionary lookup and cannot really break; what can break is a refusal
quietly becoming a default.

## Not in this slice

The real recipe engine · notifications · QC tiers · the LLM path · the auto-approval
clock · anything at all on fgcz-h-082.

Also not here: a dataset spanning **two** orders. `check_order_ids` leaves the scalar null
in that case and fills an `order_ids` array instead, and the REST API does not expose that
array — so such a dataset cannot be found by order. Recorded, not worked around.
