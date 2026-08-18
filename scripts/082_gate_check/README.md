# 082_gate_check — what are the three write gates actually doing on this node?

`docs/082-write-cutover-plan.md` §3 names three independent gates that deny writes on the
production node:

1. the Rack write policy (`Middleware::SushiReadOnlyGuard`),
2. `ApiToken#can_write?` on both bearer surfaces,
3. the **absent `capabilities` column** in 082's `api_tokens`, which makes
   `effective_capabilities` fail-closed to `["read"]` for every token.

These scripts assert that state on whichever node they run on, for the two moments where
getting it wrong is expensive: **Phase 3 step 12/13** (the write-credential code is deployed
to production but must grant nothing) and **Phase 4 step 15** ("re-prove the negative space
FIRST, before submitting anything").

## Two scripts, because they answer different questions

| script | question |
|---|---|
| `run.sh` → `verify_gates.rb` | what do the credentials and the policy **objects** say, on the real boot path? Needs no HTTP. |
| `probe_http.sh` | which gate actually **answers first** over the wire, and what does it tell the caller? |

The second is not redundant: only a real request shows the ordering, and during a cutover
"403" on its own is the least useful thing a log can say. The first is not redundant either
— for a long time the harness denied mutating HTTP verbs against production, so it was the
only way to see inside at all, and it remains the only one that needs no server running.

## Usage

    bash scripts/082_gate_check/run.sh                 # uses run_backend_082.sh
    bash scripts/082_gate_check/run.sh run_backend_083.sh

    SUSHI_PROBE_TOKEN=<read bearer> bash scripts/082_gate_check/probe_http.sh \
        http://fgcz-h-082.fgcz-net.unizh.ch:3010 read_only

`probe_http.sh` takes the expected posture as an **argument** rather than asking the server.
Stating the expectation and then checking it is the point; a probe that asks the server what
to expect cannot fail. Run it with the **read** credential in either posture — at Phase 4
that is exactly step 15's "a second (read-only) credential still cannot write". Every probe
is inert by construction, so a wrongly-open gate still could not create anything:
`/v1/datasets/validate` performs no write by design, the job POST carries an empty body, and
the DELETE targets a nonexistent id.

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

## Results on 2026-08-18 (Phase 3 steps 12 and 13)

Both scripts were validated **in both directions**, because a check that only ever passes
has not been tested.

`verify_gates.rb`, on 082 running `feat/082-env-write-credential` @ `3df6fbc` read-only —
**19/19 pass, exit 0**. On 083, running `main` and therefore without the write-credential
code — **a clean reported failure at check 0 and exit 1**, not a crash, explicitly declining
to run the remaining assertions rather than passing them vacuously. (The write API is probed
with `respond_to?` / `const_defined?` before anything calls it, for exactly that reason.)

`probe_http.sh`, against 082 asserting `read_only` — **5/5 matched, exit 0**:

| probe | gate that answered |
|---|---|
| `POST /api/v1/jobs` | 1 — Rack, `read_only` |
| `DELETE /v1/datasets/999999999` | 1 — Rack, `read_only` |
| `POST /v1/datasets/validate` | **2 — token**, `action not permitted for this token` |
| `GET /api/v1/projects/3071/datasets` | project scope, `Project not accessible` |
| `GET /internal/legacy/jobs` | `internal bridge requires a machine token` |

The third row is the one that carries the argument: `validate` is on the Rack layer's
dry-run allowlist, so it **passes gate 1** and its denial can only have come from gate 2.
Two POSTs, two different gates, each naming itself — the gates are observably independent on
production rather than merely believed to be.

Asserting the wrong posture (`additive` against a `read_only` node) correctly produced
**1 of 4 mismatched, exit 1**.

Nothing was written: `api_tokens`, `data_sets` and `jobs` counts **and max(id)s** were
identical before and after the probes (28/28, 82737/114385, 476893/483885), with zero error
lines in the log.
