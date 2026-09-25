# Running the OMAKASE demo as another user (fgcz-h-083, test instance)

Anyone in `SG_Employees` can run the demo under their own account: their own record, their
own key, their own approvals. Nothing here touches production; the backend is fgcz-h-083
with its **test database**, and B-Fabric is the **TEST** instance.

```
your account on fgcz-h-083
  └─ python3 -m omakase_core.omakase …   (code: /srv/sushi/masa_test_new_sushi_20260527/scripts)
       ├─ your record:  ~/.omakase/test/omakase.sqlite3, runs/, outbox/
       ├─ your key:     ~/.omakase/test/backend_token   (mode 600, from the 083 operator)
       └─ HTTP ─▶ backend API fgcz-h-083:3010 ─▶ SUSHI apps ─▶ job manager ─▶ SLURM
```

## What the demo can and cannot do

- Project **35611** only: every demo key is scoped to it, because that is where the demo
  data is (dataset 9, mouse RNA-seq, 2 samples).
- One order: **35755**, from the hand-made file in this directory
  (`order_35755_chain_fixture.json`). On B-Fabric TEST that order is actually `canceled`;
  the file stands in for "an order reached processed". The B-Fabric person id was removed
  from this copy.
- A recipe can be proposed **once** per order + dataset + recipe version (a database UNIQUE
  constraint, on purpose). To show it again, reset your record (step 8).
- The web panel (:8770) belongs to the operator's account. Other users use the terminal.
- Seeing results in Omics-Studio (<http://fgcz-h-083.fgcz-net.unizh.ch:4000>) needs 35611 in
  your LDAP projects. Without it, `show` still lists your jobs and output datasets.

## For the 083 operator: issue a key (once per person)

```bash
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/issue_demo_key.sh issue <login> 30
```

It creates `omakase-demo-<login>` in 083's test database (static, scope `[35611]`, may
submit, expires after 30 days; 1-90 allowed) and writes the raw key to
`~/.omakase/demo_keys/<login>.key` (mode 600). It never prints the key. Hand it over
privately, then delete your copy, so the key exists only with its owner.

```bash
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/issue_demo_key.sh list
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/issue_demo_key.sh revoke <id>
```

`revoke` refuses any id that is not an `omakase-demo-` key.

## For the user: run the demo

Log in to fgcz-h-083 and run these one at a time.

```bash
# 0. once: save the key you were given (paste it, press Enter, then Ctrl-D)
mkdir -p ~/.omakase/test && (umask 077; cat > ~/.omakase/test/backend_token)

# 1. the Python environment and the code
source /usr/local/ngseq/miniforge3/etc/profile.d/conda.sh
conda activate gi_py3.12.8
cd /srv/sushi/masa_test_new_sushi_20260527/scripts
export PYTHONDONTWRITEBYTECODE=1

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

What each step does underneath (which backend call, what is recorded) is in
[`docs/omakase-operation-quickstart.md`](../../docs/omakase-operation-quickstart.md).

## If something is refused

| Message | Meaning |
|---|---|
| `no backend token: set NEWSUSHI_TOKEN_083 or make … readable` | Step 0 is missing: no `~/.omakase/test/backend_token` |
| `refusing …/backend_token: mode 640, must be 600` | Run `chmod 600 ~/.omakase/test/backend_token` |
| `HTTP 401` | The key is wrong, revoked or expired; ask for a new one |
| `HTTP 403 … Project not accessible` | The key is not scoped to the project |
| `candidate N already exists … nothing to do` | Already proposed; reset (step 8) to propose it again |
| `DECLINED: no recipe matches` | Automatic choice found nothing; name a recipe with `--recipe` |
| `STOP: a chain is still running` (reset) | Wait until `run` finishes |
