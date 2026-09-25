# OMAKASE — operating it by hand (test instance, fgcz-h-083)

A pedestrian walkthrough: the same four actions from the web panel, from a terminal, and
from Claude Code. Written 2026-09-25 for a hands-on session. That day, steps 2-8 were run
from the terminal against a scratch record, the panel buttons were used on the live panel,
and the reset was tested on a copy of the record.

## What runs where

```
Web panel (OMAKASE tab) ─┐
Terminal (command line) ├─▶ OMAKASE engine (omakase_core, Python) ─▶ backend API :3010 ─▶ SUSHI apps
Claude Code (Bash)      ─┘         │                                   (Omics-Studio)        job manager
                                   └─ its own record: ~/.omakase/test/omakase.sqlite3         SLURM
```

- The three entry points call **the same engine**; the web panel's buttons literally run
  the command line. No language model is involved in proposing, approving or running.
- The panel's chat box (and Hermes) is a different route: an AI submits single jobs
  through the backend API. It does not drive the OMAKASE engine today.
- Test instance = B-Fabric **TEST** + the fgcz-h-083 backend and its **test database**.
  Nothing here touches production.

## Limits of the test setup (as of 2026-09-25)

- One project only: the engine's key on 083 (`apitoken:chain`) is scoped to **p35611**.
- One order only: **35755**, from a hand-made file
  (`~/.omakase/test/fixtures/order_35755_chain_fixture.json`). On B-Fabric TEST that
  order is actually `canceled`; the file stands in for "an order reached processed".
- The order list is local state, not a live view of B-Fabric.
- A recipe can be proposed **once** per order + dataset + recipe version (a database
  UNIQUE constraint, on purpose). To show it again, reset the demo (below).
- The engine runs as `masaomi` and keeps its record in that home directory.

## The walkthrough

| # | Action | Web panel | What happens underneath |
|---|---|---|---|
| 1 | See the orders that can be proposed | OMAKASE tab, "Orders with an order record" | Reads local files only; B-Fabric is not queried. There is no list command yet |
| 2 | See the recipes | the recipe drop-down on the order | Reads the recipe YAML files |
| 3 | Would a recipe be chosen automatically? | choose "automatic", press Propose | Today: 0 of 17 match (every fixture's `match` is empty, the catalog's wording does not fit), so automatic declines |
| 4 | Propose a named recipe | choose `rnaseq_meeting_shape`, press **Propose** | `GET /api/v1/projects/35611/datasets` finds the dataset whose `Order Id [B-Fabric]` column is 35755 (dataset 9); `GET /api/v1/datasets/9` reads `Species` = Mus musculus, which picks the genome from `/srv/GT/reference-favorite` (GRCm39, Release M37). Writes candidate + steps to SQLite, and a notification to `outbox/` (not e-mailed) |
| 5 | Look at the proposal | the card under "Proposals awaiting a decision" | SQLite only |
| 6 | Approve | type your name, press **Approve** | SQLite only. Nothing runs before this |
| 7 | Try without submitting | **Dry run** | Prints what would be submitted |
| 8 | Run the chain | **Run chain** | `POST /api/v1/jobs` for FastQC, FastqScreen and STAR together; the job manager hands them to SLURM; `GET /api/v1/jobs/:id` until COMPLETED; then FeatureCounts on STAR's output. About 11 minutes (10 min 55 s on 2026-09-25) |
| 9 | See the result in Omics-Studio | — | <http://fgcz-h-083.fgcz-net.unizh.ch:4000/projects/35611/datasets> (sign in with B-Fabric TEST or LDAP). Outputs are named `omakase_c<candidate>_s<step>_<App>` |
| 10 | Reset the demo | **Reset demo** (test profile only) | Moves the store, run logs and outbox to `~/.omakase/archive/demo_resets/<time>/`. Nothing is deleted. Refused while a chain runs. Candidate numbers restart at 1 |

The same steps from a terminal. Run them from the scripts directory; `--profile test` is
the default, so it is not written. Replace `1` with the candidate number that step 4
prints.

```bash
cd /srv/sushi/masa_test_new_sushi_20260527/scripts

# 1. orders that can be proposed
ls ~/.omakase/test/fixtures ~/.omakase/test/events

# 2. recipes
python3 -m omakase_core.omakase recipes

# 3. would any recipe be chosen automatically?
python3 -m omakase_core.omakase match --event ~/.omakase/test/fixtures/order_35755_chain_fixture.json --dataset 9

# 4. propose a named recipe
python3 -m omakase_core.omakase ingest --event ~/.omakase/test/fixtures/order_35755_chain_fixture.json --recipe rnaseq_meeting_shape

# 5. all proposals, then one
python3 -m omakase_core.omakase show
python3 -m omakase_core.omakase show --candidate 1

# 6. approve
python3 -m omakase_core.omakase approve --candidate 1 --actor <your name>

# 7. dry run
python3 -m omakase_core.omakase run --candidate 1 --dry-run

# 8. run the chain
python3 -m omakase_core.omakase run --candidate 1

# 10. reset the demo
bash ~/omakase_demo_reset.sh
```

Worked example, 2026-09-25 12:00 (terminal, scratch record): order 35755 → dataset 9 →
`rnaseq_meeting_shape@2` → approved → jobs 836 FastQC, 837 FastqScreen, 838+839 STAR,
840+841 FeatureCounts → datasets 873–876, DONE, no retries.

## From Claude Code

Claude Code runs the same commands through its shell, so plain requests work, for example:

- "List the OMAKASE recipes." → step 2
- "Propose rnaseq_meeting_shape for order 35755 on the test profile." → step 4
- "Show candidate 1." → step 5
- "Approve candidate 1 as <your name>." → step 6. The approval records a person's name;
  an agent should approve only when that person has said so.
- "Run candidate 1 and tell me when it is done." → step 8

## Another user running the demo

Under their own account, with their own record and key: see
[`scripts/omakase_demo/README.md`](../scripts/omakase_demo/README.md) (operator: issue a key
with `issue_demo_key.sh`, check it with `selftest_key.sh`; user: steps 0-8).

## Where things are

| What | Where |
|---|---|
| Web panel | `http://fgcz-h-083.fgcz-net.unizh.ch:8770/?key=<access key>` (key from the panel's `.env`; the cookie remembers it) |
| Engine code and its README | `scripts/omakase_core/` in this repository |
| The record (SQLite), notifications, run logs | `~/.omakase/test/` |
| Omics-Studio (to see jobs and datasets) | `http://fgcz-h-083.fgcz-net.unizh.ch:4000` |
