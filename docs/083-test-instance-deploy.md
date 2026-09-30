# Deploying the test instance on fgcz-h-083

How the operator (masaomi) brings the fgcz-h-083 **test** instance up to date and restarts
it, part by part, and how to check each part. Written 2026-09-30 from what was running that
day, read from the node (ports, screens, launchers), not from memory.

Who this is for: the operator. Users read [083-demo-quickstart.md](083-demo-quickstart.md)
(Omics-Studio) and [../scripts/omakase_demo/TEAM.md](../scripts/omakase_demo/TEAM.md)
(the shared OMAKASE panel). The production counterpart is the kit in `~/omakase_082_deploy/`
(`deploy_panel_082.sh`, `grant_write_082.sh`).

## What runs on 083

```
 browser ──▶ Omics-Studio :4000 (next dev) ──▶ backend :3010 (Rails, dev mode, key required)
 browser ──▶ OMAKASE panel :8770 ──┬─ engine (python -m omakase_core.omakase, one per click)
                                   │     └─▶ backend :3010 with the team key omakase-team-083
                                   └─ chat ──▶ FGCZ vLLM (on-prem) | hermes 127.0.0.1:8642
 backend :3010 ──▶ MySQL on 083 (the TEST database, not production)
 job_manager (trxcopy) ──polls MySQL──▶ sbatch ──▶ SLURM ──▶ results in the REAL gStore
 B-Fabric: TEST only (fgcz-bfabric-test.uzh.ch); 083's jobs register nothing in B-Fabric
```

| Part | Port | Runs as | Started by | Log | Restart with |
|---|---|---|---|---|---|
| Backend (Rails, `RAILS_ENV=development`, `LEGACY_DATABASE=true`) | 0.0.0.0:3010 | masaomi, `nohup` | `run_backend_083.sh` (gitignored), called by `restart_backend_083.sh` | `/tmp/newsushi_3010.log`, `backend/log/development.log` | `bash ~/omakase_082_deploy/restart_backend_083.sh` |
| Omics-Studio frontend (`next dev`) | 0.0.0.0:4000 | masaomi | by hand, `NEXT_PUBLIC_API_URL=http://fgcz-h-083.fgcz-net.unizh.ch:3010` | none (not in a screen, see Traps) | step 3 below |
| OMAKASE panel (FastAPI) | 0.0.0.0:8770 | masaomi, screen `kairos-agent` | `/srv/sushi/kairos_agent_server_dev/run.sh` (reads `.env`) | `/tmp/kairos_agent_8770.screenlog` | `bash ~/omakase_082_deploy/restart_chat_083.sh` |
| hermes gateway (chat relay) | 127.0.0.1:8642 | masaomi, screen `hermes-gateway` | `run_hermes_gateway.sh` (restarts hermes within 5 s if it dies) | `/tmp/hermes_gateway_8642.screenlog` | same script |
| job_manager (`start_sushi_jobmanager.py -b`) | — | **trxcopy** | not ours to start | — | not ours (no sudo); only count it |
| MySQL `sushi` (test DB) | socket | system | system | — | — |

The panel's `.env` holds, by name: `KAIROS_AGENT_HOST`, `KAIROS_AGENT_PORT`,
`KAIROS_AGENT_TOKEN` (the operator key), `NEWSUSHI_TOKEN_083` (the team backend key) and
`KAIROS_UPSTREAM` (`vllm` or `hermes`). No `OMAKASE_PROFILE`, so the profile is `test`.
Never print these values.

## What needs a restart after a code change

| Changed | Takes effect |
|---|---|
| `scripts/omakase_core/`, `scripts/omakase_order_watch/` (the engine) | on the next command or button click; no restart |
| `backend/app/` | at once (development mode reloads it) |
| `backend/config/`, `backend/lib/middleware/`, initializers, `Gemfile` | only after a backend restart |
| the panel (`kairos_agent_server_dev/kairos_agent/*.py`) | only after a panel restart (`static/index.html` is re-read from disk at once, so an old server can serve a new page: restart anyway) |
| `hermes_home/config.yaml` | only after a hermes restart |
| `frontend/` source | at once (`next dev` hot reload); `package-lock.json` needs `npm ci` + a restart |

## The procedure, in order

Run everything on fgcz-h-083 as masaomi. Every script stops at the first surprise (exit 2)
and prints no key.

### 0. Before you start

```bash
# nothing may be mid-chain (restart_backend_083.sh checks this too)
ps -u masaomi -o pid,args | grep '[o]makase_core.omakase run'

# exactly ONE job_manager, or every job is submitted twice (see Traps)
ps -eo user,pid,args | grep '[s]tart_sushi_jobmanager'
```

### 1. The code

The New SUSHI checkout on 083 **is** the development tree
(`/srv/sushi/masa_test_new_sushi_20260527`), shared by parallel sessions. There is nothing to
pull: what is committed there is what runs. It carries two local-only modifications that must
never be committed: `.gitignore` and `backend/config/database.yml`.

The panel (`/srv/sushi/kairos_agent_server_dev`) is a local git repository with no remote.

### 2. The backend

```bash
bash ~/omakase_082_deploy/restart_backend_083.sh
```

It exports `SUSHI_REQUIRE_AUTH=1`, `ENABLE_LDAP=1`, `BFABRICPY_CONFIG_ENV=TEST`,
`LEGACY_APPS_DIR=/srv/sushi/prod_apps_082_snapshot_20260818/lib` and
`LEGACY_APPS_ALLOWLIST=<the default 17>,ScSeuratCombine`, then calls `run_backend_083.sh`,
which stops the old puma (pidfile), reuses the pinned `backend/.secret_key_base_083` (so every
issued key survives), and starts the new one with `nohup`. Then it checks: no key -> 401,
wrong key -> 401, the operator key -> 200, the new env by name. The backend is down for
30-60 s.

**Never run `run_backend_083.sh` on its own.** It does not set `SUSHI_REQUIRE_AUTH` or
`ENABLE_LDAP` itself, so the backend comes up **without authentication**: any request, with
no key or a revoked one, is served as `anonymous` and may submit to any project. That is how
083 ran auth-free from 2026-09-24 11:21 to 2026-09-29 16:10.

### 3. Omics-Studio (only when it died or `package-lock.json` changed)

The running `next dev` was started 2026-09-04 from an agent shell, not in a screen. To
replace it by one that survives and logs (NOT yet run in this form):

```bash
cd /srv/sushi/masa_test_new_sushi_20260527/frontend
ps -u masaomi -o pid,args | grep '[n]ext dev --port 4000'      # the old one: note its pid, stop it
# npm ci --no-audit --no-fund                                  # only if package-lock.json changed
screen -dmS omics-studio-083 -L -Logfile /tmp/omics_studio_4000.screenlog \
  env NEXT_PUBLIC_API_URL=http://fgcz-h-083.fgcz-net.unizh.ch:3010 \
  npx next dev --port 4000 --hostname 0.0.0.0
```

### 4. Permissions (after any code change)

```bash
bash ~/omakase_082_deploy/fix_perms_083.sh
```

Removes GROUP write from the panel code, the engine code, `~/.omakase` and `~/.kairos_agent`.
Every panel click runs the engine as masaomi with the team key in its environment, so a file
another SG_Employees member could edit would run as masaomi on the next click.

### 5. The team backend key (first time, after 90 days, or when projects were added)

```bash
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/issue_team_key.sh issue    # first time
bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_demo/issue_team_key.sh refresh  # renew
```

`omakase-team-083` (api_tokens id 8 on 2026-09-29): static, read+write, scope = every
project in 083's database at issue time, 90 days. The script writes it into the panel's
`.env` (`NEWSUSHI_TOKEN_083`) and hermes' `.env` (`OMAKASE_TEAM_TOKEN_083`), with
`.env.bak-<time>` backups (mode 600, git-ignored: they hold secrets).

### 6. Panel and chat

```bash
bash ~/omakase_082_deploy/restart_chat_083.sh
```

Restarts hermes (screen `hermes-gateway` brings it back within 5 s with the current
`config.yaml`), restarts the panel in screen `kairos-agent`, and stops an old `:8771` if one
is left. To force hermes to re-read its config first: `touch hermes_home/config.yaml`.

### 7. Keys for people

```bash
cd /srv/sushi/kairos_agent_server_dev
python3 -m kairos_agent.keys issue alice          # URL in ~/.kairos_agent/issued/alice.url (600)
python3 -m kairos_agent.keys list
python3 -m kairos_agent.keys revoke alice
python3 -m kairos_agent.keys self-issue status    # "Get my key" on the first page: on|off
```

Hand the URL over privately (not in a chat, not in an AI tool), then delete the file. Details
in TEAM.md, Part 2.

## Checks

| Part | Command | Expected |
|---|---|---|
| backend up | `curl -s -o /dev/null -w '%{http_code}\n' http://fgcz-h-083.fgcz-net.unizh.ch:3010/up` | `200` |
| backend requires a key | `curl -s -o /dev/null -w '%{http_code}\n' http://fgcz-h-083.fgcz-net.unizh.ch:3010/api/v1/projects` | `401` |
| Omics-Studio | `curl -s -o /dev/null -w '%{http_code}\n' http://fgcz-h-083.fgcz-net.unizh.ch:4000/login` | `200` |
| panel requires a key | `curl -s -o /dev/null -w '%{http_code}\n' http://fgcz-h-083.fgcz-net.unizh.ch:8770/api/health` | `401` |
| hermes | `ss -ltn 'sport = :8642'` | one `LISTEN` on 127.0.0.1 |
| job_manager | `ps -eo user,args \| grep -c '[s]tart_sushi_jobmanager'` | `1` |
| the engine | `omakase_cli submits` (PATH setup: [omakase-operation-quickstart.md](omakase-operation-quickstart.md)) | `CAN SUBMIT: profile 'test' submits with its one backend key` |
| a person | open the panel with a member URL | `signed in as <name>` in the OMAKASE tab |

A real sign-in to Omics-Studio in a browser after the backend restart of 2026-09-29 has
**not been confirmed yet** (only `/login` answering 200).

## Traps

- **`run_backend_083.sh` alone = no authentication** (step 2).
- **Two job_managers** make every job run twice and `jobs.status` last-writer-wins: a row can
  read FAILED while its results are complete. It has come back after being stopped; count
  before trusting a status. Stopping one needs trxcopy (the operator has no sudo).
- **`pgrep -f 'puma.*3010'` matches your own shell.** Find the backend by its socket:
  `ss -ltnp 'sport = :3010'`.
- **A SUSHI output dataset existing does not mean its job succeeded** (FastqScreen10x on
  dataset 819: the dataset exists, job 768 FAILED). Check the job status and its log.
- **Results land in the real gStore** (`/srv/gstore/projects/p<N>/`), even though the
  database is a test one.
- **The user shell is zsh**: do not paste a command with an inline `#` comment into it (zsh
  runs `#` as a command). The comments in the blocks above are for reading; paste the command
  part only, or run the script.
- The home directory is NFS, shared with fgcz-h-082. The per-host key file
  (`~/.kairos_agent/keys_fgcz-h-083.json`) keeps 083 keys from opening the 082 panel, but
  `~/.kairos_agent/issued/` is ONE directory for both nodes: a URL issued on 082 under the
  same name overwrites the 083 one.

## Known loose ends (recorded, not fixed)

- The restart scripts live in `~/omakase_082_deploy/`, outside the repository, in a directory
  named for 082. They belong under `scripts/` (with `run_backend_083.sh` staying gitignored,
  since it holds the secret handling).
- Omics-Studio :4000 is not in a screen and has no log (step 3).
- Leftover processes from earlier experiments, all masaomi's and none serving the instance: a
  second `next dev` on :4090 (2026-08-14), and `socat` relays plus two mock vLLM servers
  (`/tmp/mockvllm/server.py`, `/tmp/fake_vllm.py`) from the firewall tests of 2026-07-23.
