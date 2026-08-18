# fgcz-h-082 write cutover — plan

**Status: Phases 0, 1 and 2 are DONE. Still no write of any kind to the 082 production
database, and no job has ever been submitted through New SUSHI on 082.**
Written 2026-08-14 against `main = 0c29fd1`; updated 2026-08-18 against `main = 55a9ec0`
after Phases 0 and 1 were executed on production with an explicit go-ahead. What remains is
Phase 3 — which had to be **reworked**, see §6 — and Phase 4, the irreversible one.

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

Verified on 083 / in the repo on 2026-08-14 unless marked otherwise. Lines marked
**[2026-08-18]** were re-verified or superseded when Phases 0 and 1 ran.

- **[2026-08-18] `main = 55a9ec0`**; `masaomi/main == origin/main == c673358`, so
  **`55a9ec0` is unpushed** — the harness denies `git push`, the user runs them.
- **[2026-08-18] 082 ran `45a7f79` and now runs `c673358`.** Phase 0 confirmed the recorded
  revision; Phase 1 fast-forwarded it the same day. The paragraph below is kept because it
  is *why* the deploy was mandatory rather than merely convenient.
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
  *(Written when a read into 082 had been declined by the harness. Verified 2026-08-18:
  082 was indeed on `45a7f79`.)*
- **082 today is read-only by construction**, running dev mode +
  `SUSHI_REQUIRE_AUTH=1` + `SUSHI_READ_ONLY=1`, authenticated by the DB-free ENV
  credential (`backend/lib/env_api_token.rb`), in screen `masa-newsushi-082` on :3010.
  Its puma binds `fgcz-h-082.fgcz-net.unizh.ch:3010`, so `curl localhost:3010` is refused
  and that is **not** evidence the instance is down.
- **The additive write policy is implemented and live-verified on 083**
  (`backend/lib/middleware/sushi_read_only_guard.rb`): DELETE and mutating PUT/PATCH → 403;
  create-only routes allowed; `/internal/*` exempt so the daemon can advance job state.
- Two cutover prerequisites were closed on 2026-08-13 (`b195175`, `0c29fd1`).
- **[2026-08-18] `LEGACY_APPS_DIR` was not set on 082 at all.** `GET
  /api/v1/application_configs` returned exactly ONE application — the native `Fastqc` — so
  none of the 17 allow-listed legacy apps was loadable, and P7 below had no valid answer.
  Fixed the same day: `run_backend_082.sh` now exports
  `LEGACY_APPS_DIR=/srv/sushi/production/master/lib`, inserted **before the final `exec`**
  because nothing after it ever runs. The endpoint now returns 18. (The route is
  `/api/v1/application_configs`; a bare `/application_configs` 404s.)
- **[2026-08-18] The app source 082 runs is NOT the one the parity work was validated
  against** — measured, not assumed. See P9 in §5.

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
was inspected on 2026-08-04 (26 rows) and again on 2026-08-18 (**28 rows**), both times
with **10 columns and no `capabilities` column** — it is legacy production SUSHI's own
table, holding real users' registration tokens, so the row count grows on its own. So on
082 today **no token can write, whatever we put in the environment and whatever row we
might insert.**

**[2026-08-18] The invariant here is the COLUMN LIST, not the row count.** The two rows
added between the inspections were a `user` + `static` pair created 2026-08-06 with a
90-day TTL — the same shape as the pair created 2026-07-23, i.e. legacy issuing ordinary
user tokens. See the corrected abort condition in §7.

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
  parsing as the existing three variables. It keeps `api_tokens` byte-for-byte untouched,
  keeps the credential out of the production DB entirely, is reversible by restarting
  without the variable, and it is exactly the escape hatch the code anticipates ("it would
  take a deliberate, reviewed code change" — `env_api_token.rb:32`).
  **Superseded by (B') — do not implement this shape.** Reading the code showed the flaw:
  the credential it would promote is the one MCP `prod-082` presents, i.e. the credential
  an AI agent reads production with. For as long as the cutover window stayed open,
  routine agent traffic could create production rows, and a human's deliberate cutover run
  would be indistinguishable from it afterwards.
- **(B') CHOSEN AND IMPLEMENTED 2026-08-14 — a SEPARATE ENV-provisioned write
  credential.** `SUSHI_ENV_TOKEN_WRITE_{SHA256,SCOPE,NAME}` alongside the existing read
  ones. The read credential is **unchanged and still read-only by construction**; the
  write credential is a different bearer value, with its own project scope and its own
  name, present in the environment only during a deliberate cutover window. Write
  authority travels on a non-database channel (`ApiToken#grant_env_write!`) because
  `capabilities` cannot be assigned where the column does not exist. The two credentials
  must differ in BOTH digest and name — sharing either is a hard boot-time configuration
  error, checked on the RAW environment values so a partly-invalid configuration cannot
  slip past it. Provision with `rake api_token:env_token WRITE=1 NAME= SCOPE=`.
  This makes "the MCP key cannot write production" permanently true, and gives production
  rows a distinct `apitoken:<name>` attribution — which is the only audit trail a
  credential with no database row can have.
- **(C) The `machine` principal** — `can_write?` returns true for it unconditionally
  (`api_token.rb:213`). **Not a path**: `machine` is infra-only; `/v1` rejects it and it is
  scoped to nothing, so it cannot submit a user job. Listing it here only so it is not
  rediscovered as a shortcut.

The (B)/(B') family has a consequence worth stating out loud: it decouples "may write" from
the production DB, so the record of who was *allowed* to write lives in the launch script and
this document, not in a table. That is a deliberate trade for not touching `api_tokens`.
(B') narrows it — because the write credential has its own name, the rows it creates are
still attributable to it, so *what was written by whom* remains answerable from the data even
though *who was permitted* is not.

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
| P1 | Confirm the revision actually deployed on 082 | **DONE 2026-08-18** — it was `45a7f79`, exactly as recorded |
| P2 | Deploy `main` (≥ `0c29fd1`) to 082 — **mandatory**, see §2 | **DONE 2026-08-18** — `c673358`, by `git merge --ff-only`, **not** rsync (see §6 Phase 1) |
| P3 | Confirm `backend/.secret_key_base_082` is pinned AND wired into the 082 launch script | **DONE** — confirmed in the launch script; tokens survived the two restarts on 2026-08-18 |
| P4 | Decide and implement the write-authority route | **DONE 2026-08-14** — route **(B')** chosen by the user and implemented; see §6 Phase 2 |
| P5 | The PRODUCTION job_manager must process a New-SUSHI-created `jobs` row identically to a legacy one | **RESTATED 2026-08-18.** User decision: **legacy and New SUSHI coexist and the job_manager is NOT changed.** So this is not a request to the daemon owner; it is a requirement on *us* — our rows and files must be indistinguishable. Evidence so far: the daemon's `read_parameters` (`masa_job_manager/src/utils.py:154`) consumes only `cores`, `ram`, `scratch`, `partition` (+ optional `gpu`, `gpu_feature`), and all of those are byte-identical to legacy's in our runs. Ordering is prepended by the daemon at sbatch time and needs nothing from us (see the 2026-08-07 dependency-chain work). |
| P6 | Choose the project scope for the first write | **decision needed** — p35611 is the natural candidate: the ENV credential is already scoped to it and it holds 18 real datasets on 082 |
| P7 | Choose the first app and input dataset | **unblocked 2026-08-18, still a decision.** It had no valid answer at all until `LEGACY_APPS_DIR` was set (§2); 082 now exposes 18 apps. Recommend the cheapest allow-listed app on a small input |
| P8 | Agree who is informed before real user-visible rows appear (rdomi / the gStore + job_manager owners) | **decision needed** |
| P9 | **The app source 082 runs must be the one our parity results were validated against** | **DONE 2026-08-18.** Every Level-2 byte-parity result was obtained against `/srv/sushi/masa_test_sushi_20260416/master/lib`; 082 runs `/srv/sushi/production/master/lib`, and **all 17 allow-listed apps differ by md5**. Measured with `scripts/prod_app_parity/`: most of that is comments and `@citation`, and the real drift is **4 apps on the input surface** (DESeq2/EdgeR gain `rankMetric`, STAR loses `getJunctions`, ScSeurat swaps two thresholds for `mLLMCelltype`) and **2 on the output surface** — STAR's `Junctions`/`Chimerics` became unconditional plus a new `DupRate`, and BWA gained `DupMetrics` gated on a default-true `markDuplicates`. Those five were **re-validated on real SLURM against the production source: 5/5 pass**, every declared output present, STAR's `strand.txt` byte-identical to the oracle and its result dir a strict superset of it. The other 13 of 18 are identical on both surfaces. |

## 6. Procedure

Each phase ends in an explicit go/no-go. Phases 0-3 write **nothing**.

### Phase 0 — re-establish the facts (no write) — **DONE 2026-08-18**
1. ~~Read 082's deployed revision, the running pid and the screen session.~~ **DONE** —
   `45a7f79` on branch `main`, puma pid 186906, screen `masa-newsushi-082` unbroken since
   2026-08-04 10:52, bound to `172.23.208.66:3010`. Working tree carried only the intended
   `backend/config/database.yml` modification.
2. ~~Re-check `api_tokens`~~ **DONE** — **28 rows / max_id 28 / 10 columns, no
   `capabilities`**. The row count differs from the recorded 26; that is legacy issuing two
   ordinary user tokens on 2026-08-06, not interference. **The abort condition as originally
   written was wrong — see §7.**
3. ~~Confirm the instance answers reads~~ **DONE** — tokenless → 401 (both `/api/v1` and
   `/internal`), invalid token → 401 (the July "dev auth-skip → 200" is gone), credential →
   200 with p35611's 18 datasets, out-of-scope → 403 `Project not accessible`, `/internal`
   with the read credential → 403 `internal bridge requires a machine token`.
   **POST/DELETE → 403 was NOT measured**: the harness denies mutating HTTP verbs against
   production. It was verified on 2026-08-04 against this same unrestarted process, so the
   property is unchanged by construction — but that is inference, not a measurement.

*Go/no-go: MET.*

### Phase 1 — deploy current code, still read-only (no DB write) — **DONE 2026-08-18**
4. ~~rsync `main` to 082~~ **DONE, but by `git fetch` + `git merge --ff-only origin/main`,
   not rsync.** 082 clones `https://github.com/fgcz/New_SUSHI_2025.git` over HTTPS and the
   update was an exact fast-forward `45a7f79..c673358`. Four reasons the substitution is
   strictly safer, and they generalise to every future deploy:
   - the range touches **no `Gemfile`, `Gemfile.lock`, `schema.rb` or migration**, so the
     July reason for mandating rsync (082 cannot build native gems) does not apply;
   - `backend/config/database.yml` is **not in the diff**, so git cannot clobber 082's
     locally modified copy — rsync only avoids that if `--exclude` is written correctly;
   - the gitignored local assets (`.secret_key_base_082`, `run_backend_082.sh`,
     `vendor/bundle`) are untouchable by git by construction;
   - **rsync would make 082's `git rev-parse HEAD` lie** (HEAD `45a7f79`, files `c673358`),
     and reading that revision is Phase 0 step 1 of this very plan. rsync poisons its own
     check for every future session.

   Rollback is one command that preserves local modifications: `git reset --keep 45a7f79`.
5. ~~Restart with the existing read-only settings, secret pinned.~~ **DONE** — new puma pid
   2958940. `run_backend_082.sh` has **no stop logic** (it ends in `exec bundle exec rails
   server`), so a restart is always `screen -S masa-newsushi-082 -X quit` — which the
   harness **does** permit, unlike `kill`/`pkill` — followed by
   `screen -dmS masa-newsushi-082 bash .../run_backend_082.sh`.
6. ~~Repeat the Phase 0 step 3 checks; confirm `api_tokens` unchanged.~~ **DONE** — every
   read check reproduced identically; `api_tokens` still 28 / 28 / 10 columns / no
   `capabilities`; boot report `EnvApiToken: ... ENABLED (name=chain-082 scope=[35611]
   principal=static capabilities=read-only)`; **zero** error or fatal log lines.
7. ~~Cross-check reads against the DB.~~ **DONE** — API `total_count` 18 == `SELECT
   COUNT(*)` 18 for p35611. Production DB is now 2621 projects / 82725 datasets / 476228
   jobs (was 2608 / 82094 / 472301 on 2026-07-16).

*Go/no-go: MET — reads are correct on the new code and nothing was written.*

### Phase 2 — write authority, implemented and reviewed on 083 (no 082 change) — **DONE 2026-08-14**
8. ~~Implement the route~~ **DONE** — (B'), a separate write credential. Red-first specs,
   fail-closed on every partial/malformed/colliding configuration, each enforcement site
   mutation-checked on its own (13 mutations across two rounds, all detected).
9. ~~Multi-LLM review~~ **DONE, two rounds.** Round 1 = **REVISE**, and it earned its keep:
   two reviewers independently found a **P1** — the read/write collision checks ran only
   when BOTH credentials parsed, so an operator who typo'd the read scope while reusing the
   read digest as the write digest would have turned the credential an agent already holds
   into a writer. One typo in a launch script from exactly what (B') exists to prevent.
   Reproduced red, then fixed by comparing the RAW environment values unconditionally.
   Also fixed: a scope list silently dropped a zero or an empty field (`0,1` → `[1]`,
   `1,,2` → `[1,2]`) instead of being refused — pre-existing, in the credential parser
   deployed on 082 today; and the write grant now refuses a **persisted** record, so a row
   from `api_tokens` cannot be promoted in-process by any caller. Round 2 = **APPROVE**
   (2/3), all round-1 P1/P2 confirmed resolved.
10. ~~Verify both gates~~ **DONE.** Request specs prove the two gates are independent and
    attribute each denial to its own gate; gate passage is asserted positively (a 422 from
    downstream of both) rather than as "not a denial", which any other 403 would satisfy.
    Also verified on the REAL boot path via `rails runner` (not only RSpec): read token
    `can_write=false`, write token `can_write=true` **while its `effective_capabilities`
    are still `["read"]`** — precisely the property needed where the column is absent — and
    the typo scenario disables both credentials and denies the read bearer outright.

Suite 532 → **577 / 0**. Nothing was deployed anywhere; 082 untouched.

*Go/no-go: MET.*

### Phase 3 — dry run on 082 (no DB write) — **REWORKED 2026-08-18, not yet run**

The original three steps do not survive contact with the harness, and step 11 hid a
decision:

- **Step 11 deploys the write-credential branch to production.** `feat/082-env-write-credential`
  (`3df6fbc`, pushed to both remotes, still unmerged) is the code that lets New SUSHI write
  the production database. Deploying it grants no authority on its own — the
  `SUSHI_ENV_TOKEN_WRITE_*` variables would be absent — but it is still the moment that code
  reaches production, and it deserves to be named rather than buried in a numbered step.
- **Steps 12-13 are POSTs, and the harness denies mutating HTTP verbs against production.**
  Proven in Phase 0: an empty-body `POST /api/v1/jobs` and a `DELETE` of a nonexistent id
  were both refused, correctly, even though three gates guaranteed a 403.

Reworked, in the order the value falls out:

11. **Decide** whether to deploy `feat/082-env-write-credential` to 082 now (read-only) or
    to defer it to Phase 4. Deploying early separates "did the deploy work" from "did we
    grant authority", which is the safer sequencing; deferring keeps production free of
    write-capable code until the day it is used.
12. If deployed: verify on the REAL boot path with **`rails runner`**, which needs no HTTP
    and leaves no orphan process — assert that the read credential reports
    `can_write? == false`, that **no** write credential is configured, and that the Rack
    policy resolves to `read_only`. This is the same technique that verified Phase 2 on 083.
13. `POST /v1/datasets/validate` (dry-run, writes nothing) and `POST /api/v1/jobs`
    (must be 403, and the body must name **which** gate refused —
    `{"error":"read_only"}` from the Rack layer vs
    `{"error":"action not permitted for this token"}` from the token layer).
    **Blocked**: needs either an explicit Bash permission rule for POSTs to
    `fgcz-h-082...:3010`, or the user running the two `curl`s. Note the gates were already
    pinned as independent, with positive gate-passage assertions, by request specs on 083 in
    Phase 2 — so this step confirms the production *environment*, not the logic.

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

- `api_tokens` **gains a `capabilities` column, or its column list changes in any way**, or
  a row relevant to us is revoked or has its principal changed.
  **[2026-08-18] This condition originally read "differs from the recorded 26 rows / 10
  columns". That was wrong and fired on the first run.** `api_tokens` is legacy production
  SUSHI's own table — as this document says in §3 — so it gains rows whenever legacy issues
  a user token, and keying the abort on the row count aborts on normal operation. The
  invariant that actually carries the argument is the **column list**: gate 3 exists purely
  because `capabilities` is absent. Record the row count and `max(id)` as context, expect
  them to grow monotonically, and investigate only a *decrease* or a non-monotonic `max(id)`.
- Any `ActiveRecord::PendingMigration` behaviour, or any log line suggesting a migration
  would run. **`LEGACY_DATABASE=true` disables `PendingMigrationError`** — its absence is
  not evidence.
- The legacy production SUSHI on :80 changes behaviour in any way.
- A dataset New SUSHI created is not visible or not filterable in the legacy UI.
- The production job_manager treats a New SUSHI row differently from a legacy one.
- gStore receives anything beyond the declared output set.
- Memory pressure on 082 — it is a 15 GB no-swap submit node with no swap and no sudo, so
  an OOM cannot be diagnosed by us.

## 8. Decisions still needed

1. ~~**Write-authority route**~~ — **ANSWERED 2026-08-14: (B')**, a separate write
   credential. Implemented and reviewed; see §6 Phase 2.
2. **Project scope** for the first write — p35611, or another.
3. **First app + input dataset**, chosen for cheapness rather than for interest.
4. **Who is told beforehand** — at minimum the job_manager/gStore owners, since the first
   New SUSHI rows will appear in a system they operate.
   *[2026-08-18] Partly settled: the user decided that legacy and New SUSHI coexist and that
   **the job_manager is not changed**. So this is no longer a request for anyone to adapt
   anything — it is a courtesy notice, and the burden of being indistinguishable sits with
   us (P5).*
5. Whether Phase 4 happens at all this month, or whether Phases 0-3 are the deliverable and
   the irreversible step waits.
6. **[2026-08-18, new] Whether to deploy `feat/082-env-write-credential` to 082 during
   Phase 3 (read-only) or only at Phase 4** — see §6 Phase 3 step 11.

**[2026-08-18] Where this now stands.** Phases 0, 1 and 2 are done and P1, P2, P3, P4 and P9
are closed; P5 is restated as a requirement on us rather than a request to the daemon owner.
None of 2-6 blocks Phase 3, which still writes nothing. Phase 4 remains gated on decisions
2, 3, 5 and its own go-ahead on the day.

## 9. Out of scope

- Public exposure of New SUSHI on 082 (Apache/Passenger vhost, production mode, real 401s,
  trxcopy ownership, systemd permanence) — deferred since 2026-07-16 and unrelated.
- B-Fabric registration. It is a separate, caller-controlled gate; the API does not fire it.
- Any DELETE or update path. `additive` denies them and this plan does not seek them.
- The frontend. It cannot submit a job at all
  (see `new_sushi_20260814_frontend_e2e_measured_form_shape_mismatch`); the cutover concerns
  the machine-callable API only.
- Extending the allow-list beyond the current 18 apps.
