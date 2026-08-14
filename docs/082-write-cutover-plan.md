# fgcz-h-082 write cutover — plan

**Status: PLAN ONLY. Nothing in this document has been executed.**
Written 2026-08-14 against `main = 0c29fd1`. No write of any kind has been made to the
082 production database, and no job has ever been submitted through New SUSHI on 082.

---

## 1. What the cutover is, and what it is not

It is **not a test**. It is the switch after which New SUSHI starts writing to the LIVE
production database and submitting to the real production job_manager → real SLURM.

fgcz-h-082 carries the production `sushi` MySQL database (2,608 projects / 82,094
datasets / 472,301 jobs as of 2026-07-16). Legacy production SUSHI serves it on :80 via
Apache/Passenger. New SUSHI coexists on :3010 as a non-public instance against **the same
database**. 083's database is a separate, isolated test DB (19 projects / 210 datasets /
777 jobs); the two share only a schema. Every job New SUSHI has ever run is on 083.

After the cutover, a single submit produces:

| Effect | Where | Undo |
|---|---|---|
| `data_sets` row(s) — output dataset, plus grandchildren | production DB | none (DELETE denied by policy, and by our own discipline) |
| `jobs` row(s) — one per fan-out unit | production DB | none |
| job script + `input_dataset.tsv` + `parameters.tsv` | gStore, under a real project | **none — gStore files are `trxcopy`-owned; we cannot delete what we put there** |
| `sbatch` by the production job_manager daemon | real SLURM | `scancel` while running only |
| result files written by the app | gStore | none |
| the new dataset appears in the legacy production UI | — | none |

The last row is the point of the exercise and also the risk: real users see it.

## 2. Verified current state

Verified on 083 / in the repo on 2026-08-14 unless marked otherwise.

- **`main = 0c29fd1`**; `masaomi/main == origin/main == main`.
- **082 is running an old revision.** Recorded as `45a7f79` (2026-08-04).
  `45a7f79..0c29fd1` is **15 commits, 11 of them touching `backend/`**, and nine of those
  eleven are legacy-parity fixes each of which would produce visibly wrong output in
  production:
  `9663a8c` project-relative `result_dir` (without it EVERY gStore link is dead and a
  chained app cannot resolve its input), `05e8114` `multi_selection` resolution,
  `73ab67e` `preprocess` + `next_dataset` ordering, `80531ed` module version pinning,
  `093804b` gStore copy set + `String#tag?`, `bb0a47c` `@name` whitespace,
  `4152a6a` `required_columns` gate + grandchild datasets, `b195175` `sushi_app_name` as
  class name, `0c29fd1` `job_parameters`.
  `b195175` matters most for coexistence: legacy's dataset filter matches
  `sushi_app_name` by regex, so before that fix New SUSHI's datasets would have been
  **invisible in the legacy production UI**.
  *(The deployed revision on 082 could not be re-checked while writing this plan — a
  read into 082 was declined. Re-verify as step P1.)*
- **082 today is read-only by construction**, running dev mode +
  `SUSHI_REQUIRE_AUTH=1` + `SUSHI_READ_ONLY=1`, authenticated by the DB-free ENV
  credential (`backend/lib/env_api_token.rb`), in screen `masa-newsushi-082` on :3010.
  Its puma binds `fgcz-h-082.fgcz-net.unizh.ch:3010`, so `curl localhost:3010` is refused
  and that is **not** evidence the instance is down.
- **The additive write policy is implemented and live-verified on 083**
  (`backend/lib/middleware/sushi_read_only_guard.rb`): DELETE and mutating PUT/PATCH → 403;
  create-only routes allowed; `/internal/*` exempt so the daemon can advance job state.
- Two cutover prerequisites were closed on 2026-08-13 (`b195175`, `0c29fd1`).

## 3. The central finding: three gates, only one of which is a config flip

The cutover is commonly described as "replace `SUSHI_READ_ONLY=1` with
`SUSHI_WRITE_POLICY=additive`". **That is not sufficient.** Three independent gates deny
writes on 082 today:

| # | Gate | Where | How it opens |
|---|---|---|---|
| 1 | Rack write policy | `lib/middleware/sushi_read_only_guard.rb:86` | **config** — set `SUSHI_WRITE_POLICY=additive` |
| 2 | Token write capability | `concerns/api_token_authenticatable.rb:57` and `v1/datasets_controller.rb:150` → `ApiToken#can_write?` (`api_token.rb:212`) | needs a token whose capabilities include `write` |
| 3 | **The `capabilities` column does not exist in the 082 `api_tokens` table** | `api_token.rb:187-207` | see below |

Gate 3 is the hard one. `effective_capabilities` **fail-closes**: if the column is absent
it logs a warning and returns `["read"]` for **every** token. The 082 `api_tokens` table
was inspected on 2026-08-04 and has **26 rows and 10 columns, with no `capabilities`
column** — it is legacy production SUSHI's own table, holding real users' registration
tokens. So on 082 today **no token can write, whatever we put in the environment and
whatever row we might insert.**

Gate 2 also blocks the credential we currently use even if the column existed: the ENV
credential is read-only *by construction* — `EnvApiToken.token_for` deliberately never
assigns `capabilities` (`env_api_token.rb:94-102`), and `write_denied_message` states
plainly that write authority "cannot be granted to it through configuration".

### The three ways out, and the recommendation

- **(A) `ALTER TABLE api_tokens ADD COLUMN capabilities` on production**, then issue a
  write-capable row (`rake api_token:issue ... CAPABILITIES=read,write`, or
  `api_token:grant_write ID=`). The migration exists:
  `backend/db/migrate/20260730140000_add_capabilities_to_api_tokens.rb`.
  **Recommend against.** This is a schema change on a table another live application owns,
  and it violates the standing rule of no schema change and no `db:migrate` on 082. It also
  cannot be reversed cleanly once legacy has been restarted against the altered table.
- **(B) A reviewed code change letting the ENV credential carry write authority** — e.g.
  `SUSHI_ENV_TOKEN_CAPABILITIES=read,write`, defaulting to read, with the same fail-closed
  parsing as the existing three variables. **Recommended.** It keeps `api_tokens`
  byte-for-byte untouched, keeps the credential out of the production DB entirely, is
  reversible by restarting without the variable, and it is exactly the escape hatch the
  code anticipates ("it would take a deliberate, reviewed code change" —
  `env_api_token.rb:32`). It must ship with specs and a multi-LLM review, like every other
  authority change in this backend.
- **(C) The `machine` principal** — `can_write?` returns true for it unconditionally
  (`api_token.rb:213`). **Not a path**: `machine` is infra-only; `/v1` rejects it and it is
  scoped to nothing, so it cannot submit a user job. Listing it here only so it is not
  rediscovered as a shortcut.

Option (B) has a consequence worth stating out loud: it decouples "may write" from the
production DB, so the audit trail for who was allowed to write lives in the launch script
and this document, not in a table. That is a deliberate trade for not touching `api_tokens`.

## 4. Reversibility — authority vs effects

**Authority is fully reversible. Effects are not.**

Restarting 082 without `SUSHI_WRITE_POLICY` / without the write capability returns the
instance to read-only in one restart. But every row, every gStore file and every SLURM job
created before that restart is permanent (see the table in §1). There is no rollback that
un-creates a production dataset.

The plan is therefore built around **making the first write as small as possible**, not
around being able to undo it.

## 5. Prerequisites

| id | Prerequisite | Status |
|---|---|---|
| P1 | Confirm the revision actually deployed on 082 | not done (read declined) |
| P2 | rsync `main` (≥ `0c29fd1`) to 082 — **mandatory**, see §2 | not done |
| P3 | Confirm `backend/.secret_key_base_082` is pinned AND wired into the 082 launch script | fixed 2026-08-04; re-verify |
| P4 | Decide and implement the write-authority route — **(B) recommended** | **decision needed** |
| P5 | Confirm the PRODUCTION job_manager daemon processes a New-SUSHI-created `jobs` row identically to a legacy one | **not verifiable on 083** — 083's daemon is doubled and is masaomi's, 082's is trxcopy's. Needs the daemon owner. |
| P6 | Choose the project scope for the first write | **decision needed** — p35611 is the natural candidate: the ENV credential is already scoped to it and it holds 18 real datasets on 082 |
| P7 | Choose the first app and input dataset | **decision needed** — recommend the cheapest allow-listed app on a small input |
| P8 | Agree who is informed before real user-visible rows appear (rdomi / the gStore + job_manager owners) | **decision needed** |

## 6. Procedure

Each phase ends in an explicit go/no-go. Phases 0-3 write **nothing**.

### Phase 0 — re-establish the facts (no write)
1. Read 082's deployed revision, the running pid and the screen session.
2. Re-check `api_tokens`: row count, `max(id)`, column list. Expect 26 / 26 / 10 columns
   without `capabilities`. **If this has changed, stop** — someone else has touched the
   table.
3. Confirm the current instance answers reads: tokenless → 401, credential → 200,
   out-of-scope → 403, `/internal` → 403, POST/DELETE → 403.

*Go/no-go: the observed state matches this document.*

### Phase 1 — deploy current code, still read-only (no DB write)
4. rsync `main` to 082. Do **not** change any environment variable yet.
5. Restart with the existing read-only settings, secret pinned.
6. Repeat the Phase 0 step 3 checks. Confirm `api_tokens` is byte-identical afterwards.
7. Cross-check a handful of reads against the DB (project counts, one project's dataset
   count) exactly as on 2026-07-16, to prove the new code reads production correctly.

*Go/no-go: reads are correct on the new code and nothing was written.*

### Phase 2 — write authority, implemented and reviewed on 083 (no 082 change)
8. Implement route (B) on a branch: `SUSHI_ENV_TOKEN_CAPABILITIES`, fail-closed, defaulting
   to read-only; red-first specs including the negative (absent variable ⇒ still read-only);
   mutation-check each enforcement site separately.
9. Multi-LLM review of the diff — this is an authority change.
10. Verify on 083 that the variable alone flips nothing without `SUSHI_WRITE_POLICY`, and
    vice versa: **both** gates must be open before a write succeeds.

*Go/no-go: review clean, suite green, both-gates behaviour proven on 083.*

### Phase 3 — dry run on 082 (no DB write)
11. Deploy the reviewed code to 082, still `SUSHI_READ_ONLY=1`, still no write capability.
12. `POST /v1/datasets/validate` (the dry-run allowlist) — passes the Rack gate, writes
    nothing.
13. Confirm POST /api/v1/jobs is still 403, and note **which** gate denies it.

*Go/no-go: the denial comes from the expected gate, with the expected message.*

### Phase 4 — the first production write (IRREVERSIBLE)
**Requires explicit go-ahead on the day, naming the project, the app and the input
dataset.** Not covered by agreeing to this plan.

14. Restart 082 with `SUSHI_WRITE_POLICY=additive` **and** the write capability, scoped to
    the single project chosen in P6.
15. Re-prove the negative space FIRST, before submitting anything: DELETE → 403,
    mutating PUT/PATCH → 403, an out-of-scope GET → 403, a second (read-only) credential
    still cannot write.
16. Submit **one** job, cheapest app, smallest input.
17. Watch it as a production job: `sacct --allusers` for the SLURM record, the result
    directory for the outputs, and the legacy production UI for whether the dataset appears
    and is filterable. **Judge by `sacct` + the result directory, never by `jobs.status`.**
18. Compare the output dataset against a legacy oracle in the same project.

*Go/no-go: one job, end to end, indistinguishable from a legacy run.*

### Phase 5 — decide the steady state
19. Either keep `additive` (and record who may write, and how the capability is revoked),
    or restart back to read-only until a wider decision is made.

## 7. Abort conditions

Stop immediately, restart 082 read-only, and report if any of these appear:

- `api_tokens` differs from the recorded 26 rows / 10 columns at any point.
- Any `ActiveRecord::PendingMigration` behaviour, or any log line suggesting a migration
  would run. **`LEGACY_DATABASE=true` disables `PendingMigrationError`** — its absence is
  not evidence.
- The legacy production SUSHI on :80 changes behaviour in any way.
- A dataset New SUSHI created is not visible or not filterable in the legacy UI.
- The production job_manager treats a New SUSHI row differently from a legacy one.
- gStore receives anything beyond the declared output set.
- Memory pressure on 082 — it is a 15 GB no-swap submit node with no swap and no sudo, so
  an OOM cannot be diagnosed by us.

## 8. Decisions needed before Phase 2 starts

1. **Write-authority route** — (A) production schema change, or **(B) ENV capability**
   (recommended), or something else.
2. **Project scope** for the first write — p35611, or another.
3. **First app + input dataset**, chosen for cheapness rather than for interest.
4. **Who is told beforehand** — at minimum the job_manager/gStore owners, since the first
   New SUSHI rows will appear in a system they operate.
5. Whether Phase 4 happens at all this month, or whether Phases 0-3 are the deliverable and
   the irreversible step waits.

## 9. Out of scope

- Public exposure of New SUSHI on 082 (Apache/Passenger vhost, production mode, real 401s,
  trxcopy ownership, systemd permanence) — deferred since 2026-07-16 and unrelated.
- B-Fabric registration. It is a separate, caller-controlled gate; the API does not fire it.
- Any DELETE or update path. `additive` denies them and this plan does not seek them.
- The frontend. It cannot submit a job at all
  (see `new_sushi_20260814_frontend_e2e_measured_form_shape_mismatch`); the cutover concerns
  the machine-callable API only.
- Extending the allow-list beyond the current 18 apps.
