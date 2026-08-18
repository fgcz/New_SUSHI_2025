# 082_gate_check — what are the three write gates actually doing on this node?

`docs/082-write-cutover-plan.md` §3 names three independent gates that deny writes on the
production node:

1. the Rack write policy (`Middleware::SushiReadOnlyGuard`),
2. `ApiToken#can_write?` on both bearer surfaces,
3. the **absent `capabilities` column** in 082's `api_tokens`, which makes
   `effective_capabilities` fail-closed to `["read"]` for every token.

This check asserts their state on whichever node it runs on. It exists because the two
moments that matter most are exactly the two where an HTTP probe is hardest to get:

- **Phase 3 step 12** — the write-credential code is deployed to production but must grant
  nothing. The agent harness denies mutating HTTP verbs against production, so `POST … → 403`
  cannot be measured from an agent session at all.
- **Phase 4 step 15** — "re-prove the negative space FIRST, before submitting anything."

## Usage

    bash scripts/082_gate_check/run.sh                 # uses run_backend_082.sh
    bash scripts/082_gate_check/run.sh run_backend_083.sh

`run.sh` **sources the launch script up to its final `exec`** instead of duplicating the
variables, so the check cannot drift from what the server actually boots with.

**It refuses any launcher that does not end in a bare `exec bundle exec rails server`, and
that refusal is load-bearing.** `run_backend_082.sh` is pure environment followed by `exec`,
so sourcing it is inert. `run_backend_083.sh` is not: it stops the previous instance first
(`kill "$OLD"`), so sourcing it would **kill the running 083 server**. Do not relax the
marker into a regex that also matches `nohup bundle exec rails s`. To check a node with a
different launcher, set the variables by hand and call
`bundle exec rails runner scripts/082_gate_check/verify_gates.rb` directly.

`REPO_DIR=` lets it run from outside the checkout — useful on a node whose deployed
revision does not carry this directory yet.

Exit code is 0 only if every check passes.

## What it asserts, and why in that order

**First, that the write-credential code is loaded at all.** Without `grant_env_write!` on
the node, every "cannot write" assertion afterwards would pass on a node that simply lacks
the feature. Order matters here: a vacuous pass is worse than a failure.

Then it adapts to the node's posture:

| posture | asserted |
|---|---|
| no write credential configured | `write_enabled? == false`, all three `SUSHI_ENV_TOKEN_WRITE_*` empty, policy `read_only` — **and** that an in-memory throwaway token granted `grant_env_write!` still reports `can_write? == true`, so a broken or no-op grant cannot masquerade as safety |
| a write credential configured | the write token writes, the **read** token still cannot, the two credentials have different names, and the policy is `additive` rather than `full` |

In both postures it asserts that the read credential cannot write, that `capabilities` is
still absent, and that `grant_env_write!` **refuses a persisted record** — which is what
makes "only the ENV credential can carry this authority" a property of the code rather than
a claim about call sites.

## The inversion that looks like a bug and is not

A write-granted token reports `can_write? == true` while its `effective_capabilities` are
still `["read"]`. That is the mechanism, not a defect: on 082 the `capabilities` column does
not exist, so authority cannot travel through it and rides
`ApiToken#env_write_granted` instead. The check asserts the inversion explicitly so nobody
"fixes" it.

## Results on 2026-08-18 (Phase 3 step 12)

Validated in both directions, because a check that only ever passes has not been tested:

- **082**, on `feat/082-env-write-credential` @ `3df6fbc`, read-only — **19/19 pass, exit 0**.
  Alongside it: every read check reproduced (tokenless 401, credential 200 with p35611's 18
  datasets, out-of-scope 403, `/internal` 403, 18 apps), `api_tokens` unchanged at 28 rows /
  10 columns / no `capabilities`, zero error lines in the log.
- **083**, on `main`, which does not carry the write-credential code — **a clean reported
  failure at check 0 and exit 1**, not a crash, and it explicitly declines to run the
  remaining assertions rather than passing them vacuously. The write API is probed with
  `respond_to?` / `const_defined?` before anything calls it, for exactly this reason.
