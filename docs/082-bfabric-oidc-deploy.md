# Enabling the B-Fabric OIDC login on 082

Written 2026-09-04, after the login was proven live on 083 (headless exchange and browser
device login, one real human sign-in at 16:08 on 2026-09-03).

Everything below was measured on the two nodes on 2026-09-04, not inferred from the design.
Where a number appears, the command that produced it is given.

## What this changes, and what it does not

| | |
|---|---|
| Adds | a second way to sign in: a B-Fabric device-code login, alongside the LDAP password login |
| Removes | nothing. The LDAP login is untouched — an LDAP-minted JWT carries no `src` claim and takes the same code path it took before |
| Write posture | **unchanged.** 082 stays `read_only`. A B-Fabric session may read; every mutating request is still refused by the Rack guard |
| Schema | **unchanged.** The deployment range contains no migration (verified: `git diff --name-status d3b2203..f3002f8 -- backend/db/` is empty) |
| Gems | **unchanged.** `backend/Gemfile` is not in the range, so no `bundle install` is needed |

### The correction that matters

The 2026-09-03 handoff described the remaining 082 work as "add the ENV variables and
restart". That was written on the assumption that the code was already deployed. It is not:

```
$ ssh fgcz-h-082 'git -C /srv/sushi/masa_test_new_sushi_20260527 rev-parse --short HEAD'
d3b2203
$ ssh fgcz-h-082 'test -f /srv/sushi/masa_test_new_sushi_20260527/backend/lib/bfabric_oidc.rb && echo YES || echo NO'
NO
```

So this is a code deployment **and** an ENV change **and** a frontend rebuild. The frontend
rebuild is required because the login page's B-Fabric block is gated at runtime on
`authStatus?.bfabric_oidc` — but that block is itself part of this deployment, and 082 serves
a production bundle built from `d3b2203`, which does not contain it.

## Why the login is write-free

This is the property that lets the feature run on a node whose database is shared with live
legacy production. It is a claim about the handler, so here is the chain:

```
GET /api/v1/auth/bfabric/session
  └─ BfabricAuthController#render_session_for
       ├─ BfabricOidc::TokenVerifier.verify   → no DB access (JWKS over HTTP, cached)
       ├─ User.find_by(login: result.sub)     → ONE SELECT
       └─ establish_session(user, …)
            └─ token_response(user, extras)   → generate_jwt_token + serialize_user
                 └─ serialize_user → current_user_project_numbers_for
                      └─ FGCZ.get_user_projects2(login)  → LDAP, no DB
```

`establish_session` never calls `issue_tokens_for`, which is the only database write a login
performs. So the absent `refresh_tokens` table on 082 is **irrelevant** to this path rather
than merely tolerated (`backend/app/controllers/concerns/session_issuing.rb:46-48`).

Verified mechanically, too — no write API is called anywhere on the path:

```
$ grep -rnE "\.(save|save!|update|update!|update_attribute|touch|increment!|create|create!|destroy)\b" \
    backend/app/controllers/api/v1/bfabric_auth_controller.rb \
    backend/app/controllers/concerns/session_issuing.rb \
    backend/app/controllers/concerns/project_authorizable.rb \
    backend/lib/bfabric_oidc.rb backend/lib/bfabric_oidc/*.rb
(no output)
```

Both routes are GETs, so `Middleware::SushiReadOnlyGuard::NO_WRITE_PATHS` does not grow.
Section 7 of the gate check pins that list at exactly two entries.

### The one write that still happens on a GET, and is not ours

`DataSet#samples_length` writes `num_samples` on a dataset GET under every policy. It
predates this work, is parity with legacy, and is unrelated to the login. It is recorded here
only so that a later reader who audits "does 082 write?" is not surprised by it.

## The environment block

All four lines go in together. `BFABRIC_OIDC_ENABLED=1` on its own fails closed — the config
records an error for the missing base URL and audience, the feature stays off, and section 8
of the gate check reports the errors.

Add to `run_backend_082.sh` (gitignored, local to 082) immediately after
`export ENABLE_LDAP=1`:

```bash
# B-Fabric OIDC login (2026-09-04). Values measured 2026-09-03, see
# scripts/bfabric_oauth_check/fixtures/measured_claims_2026-09-03.json:
# aud is the literal string API on both instances, iss equals the base URL exactly (so
# BFABRIC_OIDC_ISSUER can stay unset), and the public client CLI is device_code-registered
# on PRODUCTION as well as test.
#
# PRODUCTION issuer, deliberately. This node's `users` table is live production, so
# trusting the test issuer here would let a B-Fabric TEST account authenticate as the
# same login in production SUSHI. 083 points at test; 082 must not.
#
# The allow-list is the only per-client narrowing available today. Its limit, stated
# plainly: CLI is the PUBLIC client anyone may drive, so this blocks a token minted for a
# DIFFERENT B-Fabric client and does not block someone who deliberately uses CLI.
#
# This login performs NO database write — see docs/082-bfabric-oidc-deploy.md.
# TO REVERT: comment out these four lines and restart. Nothing else to undo.
export BFABRIC_OIDC_ENABLED=1
export BFABRIC_OIDC_BASE_URL=https://fgcz-bfabric.uzh.ch/bfabric
export BFABRIC_OIDC_AUDIENCE=API
export BFABRIC_OIDC_ALLOWED_CLIENT_IDS=CLI
```

Everything else keeps its default: `BFABRIC_OIDC_REQUIRED_SCOPE` is `api:read`,
`BFABRIC_OIDC_ISSUER` stays unset (the discovery document's own `issuer` is used), and the
browser device login is ON, which is the point of the change for human users.

## Procedure

Two stages, on purpose. Stage 1 deploys the code with the feature still OFF, so the
deployment can be proven inert before it is given any effect — the same discipline Phase 3
used ("deploy the code now so the next step changes only ENV vars"). Stage 2 is then four
ENV lines and a restart.

Expected gate-check totals, computed from the two revisions of `verify_gates.rb`:

| State | Final line |
|---|---|
| now (`d3b2203`, read-only) | `ALL 19 CHECKS PASS` |
| after stage 1 (code in, feature off) | `ALL 21 CHECKS PASS` — §7 and §8's error check are new |
| after stage 2 (feature on) | `ALL 22 CHECKS PASS` — §8 adds the audience assertion |

The totals rise because assertions were added, not because the posture loosened. **Read
`0 FAILED`, not a fixed count.**

### Stage 0 — record the starting point

```bash
ssh fgcz-h-082
R=/srv/sushi/masa_test_new_sushi_20260527
git -C $R rev-parse --short HEAD                 # expect d3b2203
bash $R/scripts/082_gate_check/run.sh            # expect ALL 19 CHECKS PASS
```

### Stage 1 — deploy the code, feature still OFF

082's tree carries two intentional local modifications, `backend/Gemfile.lock` (the
`ENABLE_LDAP` path gem) and `backend/config/database.yml` (local-only). **The deployment
range touches neither**, so the fast-forward will not conflict with them:

```
$ git diff --name-only d3b2203..f3002f8 -- backend/Gemfile.lock backend/config/database.yml
(no output)
```

082 is checked out on `feat/082-env-write-credential`, which on the remote is still at the
stale `6b49702`. `main` is now the same line of history and is ahead, so move onto `main`:

```bash
git -C $R fetch origin main
git -C $R checkout -B main origin/main           # d3b2203 is an ancestor of f3002f8: a fast-forward
git -C $R rev-parse --short HEAD                 # expect f3002f8
```

Restart the backend. The screen session has exactly one window whose process is puma itself
(the launcher `exec`s into it), so Ctrl-C would end the window and the session — stop the
process and start a fresh detached session instead:

```bash
screen -ls                                       # expect masa-newsushi-082, detached
pgrep -a -u masaomi -f 'puma.*3010'              # exactly one pid
kill <that pid>
screen -dmS masa-newsushi-082 bash $R/run_backend_082.sh
sleep 20 && curl -s -o /dev/null -w '%{http_code}\n' http://fgcz-h-082.fgcz-net.unizh.ch:3010/api/v1/auth/login_options
```

Then prove the deployment is inert:

```bash
bash $R/scripts/082_gate_check/run.sh            # expect ALL 21 CHECKS PASS,
                                                 # §8 printing requested=false enabled=false
```

Rebuild the frontend (the build is heap-capped at 3 GB because this node has 15 GB and no
swap; the launcher stops whatever holds :4000 by listening socket and refuses to hand you a
stale orphan):

```bash
bash $R/run_frontend_082.sh
```

At the end of stage 1 the UI and API behave exactly as they did before. The B-Fabric button
does not render, because the backend still answers `bfabric_oidc: false`.

### Stage 2 — enable the feature

```bash
cp $R/run_backend_082.sh $R/run_backend_082.sh.bak-before-oidc-$(date +%Y%m%d-%H%M%S)
# add the four export lines from "The environment block" above, after export ENABLE_LDAP=1
kill $(pgrep -u masaomi -f 'puma.*3010')
screen -dmS masa-newsushi-082 bash $R/run_backend_082.sh
sleep 20
bash $R/scripts/082_gate_check/run.sh            # expect ALL 22 CHECKS PASS
```

Section 8 should now print:

```
requested=true enabled=true base_url="https://fgcz-bfabric.uzh.ch/bfabric" audience="API"
client allow-list: ["CLI"]
```

If the allow-list line instead reads `NONE — any B-Fabric client is accepted`, the fourth
export did not take effect. The boot log says the same thing in one line:

```bash
grep -a 'BfabricOidc:' $R/backend/log/development.log | tail -3
```

### Verification, all read-only

```bash
B=http://fgcz-h-082.fgcz-net.unizh.ch:3010

# 1. the feature is advertised to the UI
curl -s $B/api/v1/auth/login_options            # bfabric_oidc: true

# 2. the exchange route exists and demands a bearer — 401, not 404
curl -s -o /dev/null -w '%{http_code}\n' $B/api/v1/auth/bfabric/session   # 401

# 3. the write gates are untouched (run with the READ credential)
SUSHI_PROBE_TOKEN=<read bearer> bash $R/scripts/082_gate_check/probe_http.sh $B read_only
#                                                 expect ALL 5 PROBES MATCHED
```

Then the only step no script can do: open `http://fgcz-h-082.fgcz-net.unizh.ch:4000/login`,
choose the B-Fabric sign-in, approve the code at B-Fabric **production**, and confirm the
project list appears. A login whose B-Fabric `sub` has no row in the production `users` table
is refused with `unknown_user` and no row is created — that is deliberate, and it is the same
answer the LDAP login gives.

## Rollback

Comment out the four export lines and restart. There is nothing else to undo: no migration
ran, no row was written, no file outside the launcher changed. Reverting the code as well is
a `git checkout` of the previous revision plus one more restart, but it is not needed to turn
the feature off.
