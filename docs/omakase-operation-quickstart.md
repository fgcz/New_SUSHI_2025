# OMAKASE — operating it by hand (test instance, fgcz-h-083)

A pedestrian walkthrough: the same actions from the web panel, from a terminal, from
Claude Code, and (since 2026-09-29) from the panel's chat. Written 2026-09-25 for a
hands-on session. That day, steps 2-8 were run from the terminal against a scratch
record, the panel buttons were used on the live panel, and the reset was tested on a copy
of the record.

## What runs where

```
Web panel (OMAKASE tab) ─┐
Terminal (command line) ├─▶ OMAKASE engine (omakase_core, Python) ─▶ backend API :3010 ─▶ SUSHI apps
Claude Code (Bash)      ─┤         │                                   (Omics-Studio)        job manager
Panel chat (omakase_*   ─┘         └─ its own record: ~/.omakase/test/omakase.sqlite3         SLURM
  MCP tools, FGCZ vLLM)
```

- The entry points call **the same engine**; the web panel's buttons literally run the
  command line, and the chat's `omakase_*` tools call the same functions as the buttons.
  No language model is involved in choosing a recipe, approving or running.
- The chat (vLLM direct or hermes, both on the on-prem FGCZ vLLM) can read, fetch an order
  and propose. Approve, reject, confirm and run are **requests**: nothing happens until a
  person clicks **Allow**, and that person is recorded as the approver. The kairos-chain
  tools that call a hosted LLM are never offered to it. See "From the panel's chat" below.
- Test instance = B-Fabric **TEST** + the fgcz-h-083 backend and its **test database**.
  Nothing here touches production.
- Since 2026-09-29 each profile runs on its own node only: `test` on fgcz-h-083,
  `production` on fgcz-h-082 (its own panel on port 8771, with no chat). Run
  elsewhere, the engine and the watcher exit 2 before opening a file.

## Limits of the test setup (as of 2026-09-29)

- One project only: the engine's key on 083 (`apitoken:chain`) is scoped to **p35611**.
- In practice one order: **35755**, the only order in p35611 whose data (dataset 9) is in
  083's test database. Since 2026-09-25 13:35 it is `processed` on B-Fabric TEST, so its
  real record can be fetched (step 1b); the hand-made file
  (`~/.omakase/test/fixtures/order_35755_chain_fixture.json`) is the fallback if it is not.
  Any other processed order can be fetched, but proposing on it declines (no data on 083)
  or is refused (a project outside p35611).
- The order list is local state, not a live view of B-Fabric.
- A recipe can be proposed **once** per order + dataset + recipe version (a database
  UNIQUE constraint, on purpose). To show it again, reset the demo (below).
- The engine runs as `masaomi` and keeps its record in that home directory.

## The walkthrough

| # | Action | Web panel | What happens underneath |
|---|---|---|---|
| 1 | See the orders that can be proposed | OMAKASE tab, "Orders with an order record" | Reads local files only; B-Fabric is not queried. There is no list command yet |
| 1b | Add an order by its id | "Propose on a processed order by id": type the id, press **Fetch** | The order watcher reads that one order from B-Fabric and writes its record only if its status is `processed` now (anything else is declined). It then appears in step 1's list, marked `named` |
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

# 1b. add an order by its id (a record is written only if it is processed now)
python3 -m omakase_order_watch.watch --order <order id>

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

## From the panel's chat

Keep the OMAKASE tab open on the left and type your name in its name box once (the browser
remembers it): **Allow** records that name as the approver. Then write in the chat on the
right. Each prompt below maps to one `omakase_*` tool, the panel control that does the same,
and the command line underneath. The commands run from
`/srv/sushi/masa_test_new_sushi_20260527/scripts`; replace `2` with the candidate number the
propose step reports (candidate 1 on 2026-09-29 was an earlier `fastqc_only`, already DONE).

| # | Prompt (English) | Tool | Panel | Command line |
|---|---|---|---|---|
| 1 | `What is the current OMAKASE status?` | `omakase_status` | the status card | `python3 -m omakase_core.omakase show` and `python3 -m omakase_order_watch.watch --status` |
| 2 | `Which orders can OMAKASE propose on right now?` | `omakase_orders` | "Orders with an order record" | `ls ~/.omakase/test/events ~/.omakase/test/fixtures` (no list command) |
| 3 | `Fetch order 35755 from B-Fabric.` | `omakase_fetch_order` | order id box, **Fetch** | `python3 -m omakase_order_watch.watch --order 35755` |
| 4 | `Which recipes match order 35755, and why?` | `omakase_match` | "automatic", then Propose | `python3 -m omakase_core.omakase match --event ~/.omakase/test/events/order_35755.json` |
| 5 | `List the available recipes.` | `omakase_recipes` | the recipe drop-down | `python3 -m omakase_core.omakase recipes` |
| 6 | `Propose the recipe rnaseq_meeting_shape for order 35755.` | `omakase_propose` | choose the recipe, **Propose** | `python3 -m omakase_core.omakase ingest --event ~/.omakase/test/events/order_35755.json --recipe rnaseq_meeting_shape` |
| 7 | `Show me the new proposal: the steps, parameters and genome.` | `omakase_show` | the proposal card | `python3 -m omakase_core.omakase show --candidate 2` |
| 8 | `Please approve candidate 2.` | `omakase_request_approve` → a request card → **Allow** | **Approve** | `python3 -m omakase_core.omakase approve --candidate 2 --actor <your name>` |
| 9 | `Do a dry run of candidate 2.` | `omakase_request_run` (dry run) → **Allow** | **Dry run** | `python3 -m omakase_core.omakase run --candidate 2 --dry-run` |
| 10 | `Now run candidate 2 on the cluster.` | `omakase_request_run` → **Allow** | **Run chain** | `python3 -m omakase_core.omakase run --candidate 2` |
| 11 | `What happened to my requests?` | `omakase_requests` | "Requests from the chat" | `ls ~/.omakase/test/chat_requests/` (one JSON file per request) |
| 12 | `How is the run going? Show the latest log.` | `omakase_runs`, `omakase_show` | "Chain runs" | `ls -t ~/.omakase/test/runs/` and `tail -n 40` the newest `.log` |

- Prompts 8-10 file a **request**; the model says "request … filed" and a card with
  **Allow** / **Deny** appears under its answer (and in the OMAKASE tab). Nothing happens
  until a person clicks. The command-line equivalents act at once: typing them is the
  person's release.
- Name the candidate number (prompts 7-10). It is the most reliable way to keep the model
  on the proposal you mean.
- Skip prompt 9 in a demo: on 2026-09-25 a dry run moved a candidate from APPROVED to
  RUNNING, which is recorded and not yet investigated. Go 8 → 10.
- Name the recipe (prompt 6). "Automatic" declines today: 0 of 17 recipes match.
- A given order + dataset + recipe version can be proposed once. To show the same recipe
  again, press **Reset demo** first.
- The same prompts work in Japanese; the model answers in the language it was asked in.
- vLLM direct answers in seconds. Through hermes a turn took 15-25 s on 2026-09-29,
  because hermes first looks the tool up (`tool_search`). The request card appears only
  after the answer.

## A team on the shared panel

Since 2026-09-29 each member gets their own panel key (`python3 -m kairos_agent.keys issue
<name>`), and whoever holds the key is recorded as the approver; the shared token still types
a name. The panel submits with its own backend key, `omakase-team-083`, over every 083 project,
not the operator's `chain` key. Setup and limits: [`scripts/omakase_demo/TEAM.md`](../scripts/omakase_demo/TEAM.md).

## Another user starting their own instance

Under their own account, with their own record, key and optionally their own panel: see
[`scripts/omakase_demo/README.md`](../scripts/omakase_demo/README.md) (operator: issue a key
with `issue_demo_key.sh`, check it with `selftest_key.sh`; user: the terminal steps, or
`start_panel.sh <port>` for a panel of their own).

## Where things are

| What | Where |
|---|---|
| Web panel | `http://fgcz-h-083.fgcz-net.unizh.ch:8770/?key=<access key>` (key from the panel's `.env`; the cookie remembers it) |
| Engine code and its README | `scripts/omakase_core/` in this repository |
| The record (SQLite), notifications, run logs, chat requests | `~/.omakase/test/` |
| The chat's OMAKASE tools | `kairos_agent/omakase_mcp.py` in `/srv/sushi/kairos_agent_server_dev` |
| Omics-Studio (to see jobs and datasets) | `http://fgcz-h-083.fgcz-net.unizh.ch:4000` |
