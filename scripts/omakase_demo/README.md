# Starting your own OMAKASE instance (fgcz-h-083, test instance)

> Since 2026-09-29 a team normally shares ONE panel with a key per person, which records
> who approves: see [TEAM.md](TEAM.md). This page is the other option, your own instance.

Anyone in `SG_Employees` can run OMAKASE under their own account: their own record, their
own backend key, their own approvals, and optionally their own web panel. Nothing here
touches production; the backend is fgcz-h-083 with its **test database**, and B-Fabric is
the **TEST** instance.

```
your account on fgcz-h-083
  ├─ terminal:  python3 -m omakase_core.omakase …     ┐ the same engine
  └─ your panel (optional): start_panel.sh <port>      ┘ (code: /srv/sushi/masa_test_new_sushi_20260527/scripts)
       ├─ your record:     ~/.omakase/test/omakase.sqlite3, runs/, outbox/
       ├─ your backend key: ~/.omakase/test/backend_token   (mode 600, from the 083 operator)
       └─ HTTP ─▶ backend API fgcz-h-083:3010 ─▶ SUSHI apps ─▶ job manager ─▶ SLURM
```

## What is yours and what is shared

| | Yours | Shared with everyone |
|---|---|---|
| Record (proposals, approvals, runs, notifications) | `~/.omakase/test/` | — |
| Backend key | `~/.omakase/test/backend_token`, named `omakase-demo-<login>` | — |
| Panel (optional) | its own port, screen `omakase-panel-<login>`, access key `~/.omakase/panel_key` | the panel code in `/srv/sushi/kairos_agent_server_dev` |
| Engine code, recipes, demo order | — | this repository's `scripts/`, Paul's catalog clone |
| Backend, test database, project 35611 | — | yes: everyone's jobs and output datasets land in p35611 |

## What has been checked (2026-09-25)

| Path | Status |
|---|---|
| Issue a key, then propose → approve → run from the terminal with it | **Verified.** `selftest_key.sh --run` with a throwaway key: job 844 COMPLETED, recorded as submitted by `apitoken:omakase-demo-selftest`. The key was then revoked |
| Your own panel (`start_panel.sh`) | **Written, not yet run under a second account.** Known risk: the panel's chat part starts a kairos-chain process that uses a shared knowledge-base directory; one lock file there (`storage/blockchain.json.lock`) is writable only by its owner. If the panel fails to start, send its log (`~/.omakase/panel_<port>.screenlog`) to the operator and use the terminal instead |

**Current state of the 083 backend (2026-09-25):** it has been running **without
authentication** since 2026-09-24 11:21. Requests with no key, a wrong key or a revoked key
are answered as `anonymous`. So today a key gives attribution (your jobs show up as
`apitoken:omakase-demo-<login>`), not access control. Restarting the backend with
`ENABLE_LDAP=1 SUSHI_REQUIRE_AUTH=1` restores the checks; until then the `HTTP 401` row
below does not occur.

## What the demo can and cannot do

- Project **35611** only: every demo key is scoped to it, because that is where the demo
  data is (dataset 9, mouse RNA-seq, 2 samples).
- One order: **35755**, from the hand-made file in this directory
  (`order_35755_chain_fixture.json`). On B-Fabric TEST that order is actually `canceled`;
  the file stands in for "an order reached processed". The B-Fabric person id was removed
  from this copy.
- A recipe can be proposed **once** per order + dataset + recipe version (a database UNIQUE
  constraint, on purpose). To show it again, reset your record (step 8, or **Reset demo** in
  your panel).
- Seeing results in Omics-Studio (<http://fgcz-h-083.fgcz-net.unizh.ch:4000>) needs 35611 in
  your LDAP projects. Without it, `show` still lists your jobs and output datasets.

## Part 1 — the 083 operator: issue a key (once per person)

```bash
# 1. issue: static, scope [35611], may submit, expires after 30 days (1-90 allowed)
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/issue_demo_key.sh issue <login> 30

# 2. check it end to end before handing it over (fresh scratch record, your own key unset;
#    --run submits one FastQC job, about 6 minutes, and prints who the backend recorded)
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/selftest_key.sh ~/.omakase/demo_keys/<login>.key --run

# 3. hand the key over privately (it is in ~/.omakase/demo_keys/<login>.key), then delete your copy
rm ~/.omakase/demo_keys/<login>.key
```

`issue` writes the key only to `~/.omakase/demo_keys/<login>.key` (mode 600) and never
prints it; the jobs it submits are recorded as `apitoken:omakase-demo-<login>`. The scratch
record of each self-test is kept under `~/.omakase/archive/key_selftests/<time>/`.

```bash
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/issue_demo_key.sh list
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/issue_demo_key.sh revoke <id>
```

`revoke` refuses any id that is not an `omakase-demo-` key.

## Part 2 — the user: set up once

Log in to fgcz-h-083.

```bash
# 0. save the key you were given (paste it, press Enter, then Ctrl-D)
mkdir -p ~/.omakase/test && (umask 077; cat > ~/.omakase/test/backend_token)

# 1. the Python environment and the code
source /usr/local/ngseq/miniforge3/etc/profile.d/conda.sh
conda activate gi_py3.12.8
cd /srv/sushi/masa_test_new_sushi_20260527/scripts
export PYTHONDONTWRITEBYTECODE=1
```

Then use either the terminal (A) or your own panel (B). Both use the same engine and the
same record, so you can mix them.

## Part 2A — from the terminal

```bash
# 2. the recipes
python3 -m omakase_core.omakase recipes

# 3. would any recipe be chosen automatically? (today: 0 of 17, so it would decline)
python3 -m omakase_core.omakase match --event /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/order_35755_chain_fixture.json --dataset 9

# 4. propose a named recipe (fastqc_only takes ~6 min to run; rnaseq_meeting_shape ~11 min)
python3 -m omakase_core.omakase ingest --event /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/order_35755_chain_fixture.json --recipe fastqc_only

# 5. your proposals, then one of them (use the number step 4 printed)
python3 -m omakase_core.omakase show
python3 -m omakase_core.omakase show --candidate 1

# 6. approve it, under your own name
python3 -m omakase_core.omakase approve --candidate 1 --actor <your name>

# 7. dry run, then the real run (it waits until every step is COMPLETED)
python3 -m omakase_core.omakase run --candidate 1 --dry-run
python3 -m omakase_core.omakase run --candidate 1

# 8. to propose the same recipe again: move your record aside (nothing is deleted)
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/reset_demo_store.sh
```

## Part 2B — your own web panel

```bash
# start it on a free port between 8780 and 8799
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/start_panel.sh 8781

# the address to open, with your access key (do not paste it into chats or tickets)
cat ~/.omakase/panel_url.txt

# stop it
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/start_panel.sh stop
```

`start_panel.sh` refuses to start without `~/.omakase/test/backend_token` (mode 600), copies
the demo order into `~/.omakase/test/fixtures/` so the panel lists it, creates your access
key once (`~/.omakase/panel_key`, mode 600, never on a command line), and runs the panel in
screen `omakase-panel-<login>` with its log in `~/.omakase/panel_<port>.screenlog`.

In your panel:

- The **OMAKASE tab** works as on the operator's panel: pick order 35755, choose a recipe by
  name (the default "automatic" declines today), Propose, type your name, Approve, Run
  chain. **Reset demo** moves *your* record aside.
- The **docs** link in the header opens `docs/omakase-operation-quickstart.md`.
- The **chat** runs on the FGCZ vLLM only; hermes shows as unavailable, because its settings
  are readable only by the operator. Prefer the OMAKASE tab: the chat's tools come from the
  shared knowledge base, and one of them (`llm_call`) can reach a hosted model — see the
  2026-09-25 note in L2 `omakase_20260925_architecture_qa_and_demo_prep`.

What each step does underneath (which backend call, what is recorded) is in
[`docs/omakase-operation-quickstart.md`](../../docs/omakase-operation-quickstart.md).

## If something is refused

| Message | Meaning |
|---|---|
| `no backend token: set NEWSUSHI_TOKEN_083 or make … readable` | Step 0 is missing: no `~/.omakase/test/backend_token` |
| `refusing …/backend_token: mode 640, must be 600` | Run `chmod 600 ~/.omakase/test/backend_token` |
| `HTTP 401` | The key is wrong, revoked or expired; ask for a new one. Only while the backend requires authentication (see above) |
| `HTTP 403 … Project not accessible` | The key is not scoped to the project |
| `candidate N already exists … nothing to do` | Already proposed; reset (step 8) to propose it again |
| `DECLINED: no recipe matches` | Automatic choice found nothing; name a recipe with `--recipe` |
| `STOP: a chain is still running` (reset) | Wait until `run` finishes |
| `STOP: port … is in use` (panel) | Pick another port between 8780 and 8799 |
| `STOP: you already run a panel` | `start_panel.sh stop`, then start again |
