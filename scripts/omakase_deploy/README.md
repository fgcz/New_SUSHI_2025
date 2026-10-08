# omakase_deploy — the operator's scripts for fgcz-h-082 and fgcz-h-083

Moved here from `~/omakase_082_deploy/` on 2026-09-30, so they are versioned with the code
they deploy. Run each as masaomi on the node its name says; each stops at the first surprise
(exit 2) and prints no key. They contain no secret: keys are generated, read from mode-600
files, or compared by name at run time.

| Script | Node | What it does | Undo |
|---|---|---|---|
| `restart_backend_083.sh` | 083 | restart the backend :3010 **with** authentication (`SUSHI_REQUIRE_AUTH=1`, `ENABLE_LDAP=1`, `BFABRICPY_CONFIG_ENV=TEST`), then check it | — |
| `restart_chat_083.sh` | 083 | restart hermes and the panel :8770 (screen `kairos-agent`), stop a stray :8771 | — |
| `fix_perms_083.sh` | 083 | remove group write from what the panel runs or trusts | — |
| `deploy_panel_082.sh` | 082 | the production panel :8771 (named keys, self-issue OFF, chat off); grants no write authority | `screen -S omakase-panel-prod -X quit` |
| `grant_write_082.sh` | 082 | a write credential `omakase-082-write` (project 35611 only) + `SUSHI_WRITE_POLICY=submit_only`, backend restart, gate check, 9 inert probes | `revoke_write_082.sh` |
| `revoke_write_082.sh` | 082 | back to `read_only`, write key deleted, backend restart, checks | — |
| `hand_mark_order_082.py` | 082 | ONLY if the panel's Fetch declines a p35611 order because it is not `processed` on B-Fabric PRODUCTION: writes its event marked HAND-MARKED, with the real status | delete the event file it names |

The 083 procedure (what runs, what to restart after which change, the checks) is
[`docs/083-test-instance-deploy.md`](../../docs/083-test-instance-deploy.md).

## Not in git, on purpose

- `~/omakase_082_deploy/kairos_agent_server.bundle` — the panel repository
  (`/srv/sushi/kairos_agent_server_dev`) has no remote and is not published; both remotes of
  this repository are public. `deploy_panel_082.sh` reads the bundle from there
  (`OMAKASE_PANEL_BUNDLE` overrides the path). Rebuild it on 083 after a panel commit:
  `git -C /srv/sushi/kairos_agent_server_dev bundle create ~/omakase_082_deploy/kairos_agent_server.bundle main`
- `~/omakase_082_deploy/add_catalog_082.sh` and `start_watch_082.sh` (2026-09-29, optional,
  never run) were not moved.

## fgcz-h-082, in order

`/srv/sushi` is a local disk on each node, so a script committed here reaches 082 only when
082's checkout is fast-forwarded. That is step 2, the bootstrap; `deploy_panel_082.sh` then
checks the result instead of doing it.

```
083: commit ─▶ 1 push ─▶ origin (fgcz) ─▶ 2 bootstrap on 082 (fast-forward, scripts/ + docs/ only)
082: 3 deploy_panel_082.sh ─▶ 4 a key for yourself ─▶ 5 grant_write_082.sh ─▶ 6 the browser
```

1. On 083 (the agent may not push): `git push origin main && git push masaomi main`
2. Bootstrap. It stops, and fast-forwards nothing, if the range would touch anything outside
   `scripts/` and `docs/` (the running backend would then need a restart):

   ```bash
   ssh fgcz-h-082 'cd /srv/sushi/masa_test_new_sushi_20260527 && git fetch -q origin main && git merge-base --is-ancestor HEAD origin/main && test -z "$(git diff --name-only HEAD origin/main | grep -Ev "^(scripts|docs)/")" && git merge --ff-only -q origin/main && git log --oneline -1 || echo "STOP: not fast-forwarded"'
   ```

3. `ssh fgcz-h-082 'bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/deploy_panel_082.sh'`
   — expect every check `ok` and "Run does not submit".
4. `ssh fgcz-h-082 'cd /srv/sushi/kairos_agent_server_dev && python3 -m kairos_agent.keys issue masaomi --url http://fgcz-h-082.fgcz-net.unizh.ch:8771'`
   — the URL with your key is in `~/.kairos_agent/issued/masaomi.url` (mode 600).
5. `ssh fgcz-h-082 'bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/grant_write_082.sh'`
   — backend restart (a half-finished sign-in must be started again; signed-in sessions
   survive), then the gate check, 9 probes PASS and `CAN SUBMIT`.
6. In the browser: Fetch the order. If it is declined as not `processed`, and only then:
   `ssh fgcz-h-082 'cd /srv/sushi/masa_test_new_sushi_20260527/scripts && python3 omakase_deploy/hand_mark_order_082.py 35755'`.
   Then name the recipe and the dataset, Propose, check the derived genome, Approve, Run —
   the page asks a PRODUCTION confirm naming the dataset and the project first.

The model-suggested genome (only when neither the dataset nor the order's B-Fabric samples
name a curated species) asks the FGCZ vLLM DIRECTLY on 082, since 082 runs no hermes
(route C, decided 2026-10-08; `genome_ai.route_for`). Nothing to install and no key. Check
that 082 still reaches it - expect `200`:
`ssh fgcz-h-082 'curl -s -o /dev/null -w "%{http_code}\n" --max-time 10 http://fgcz-c-056:8000/v1/models'`.
Unreachable means only that such an order is refused, as before the step existed;
`OMAKASE_GENOME_AI=off` switches the step off.

To go back to read_only at any point:
`ssh fgcz-h-082 'bash /srv/sushi/masa_test_new_sushi_20260527/scripts/omakase_deploy/revoke_write_082.sh'`
(it refuses while a chain is running).

The user shell is zsh: paste the commands as they are, with no `#` comment after them.

## What was verified, and how (2026-09-30, on 083, nothing on 082)

- `grant_write_082.sh` and `revoke_write_082.sh`, steps 0-2, against a FAKE 082-shaped
  launcher: the digest in the launcher equals the SHA-256 of the key file, the block sits
  before `exec`, the sourced environment is right, a second grant is refused, and the revoke
  restores the launcher byte-identical.
- `hand_mark_order_082.py` against a fake B-Fabric: processed -> refused, another project ->
  refused, canceled in p35611 -> written (mode 600, env PRODUCTION, real status kept), a second
  time -> refused.
- Not yet run anywhere: steps 3-5 against a live backend. In particular the gate check
  (`scripts/082_gate_check/run.sh`) in the WRITE posture with the all-projects read key.
- `scripts/082_gate_check/probe_http.sh` gives a false FAIL since 2026-09-25 (its
  out-of-scope probe assumes a project-scoped read key); `grant_write_082.sh` uses its own
  probes instead.
