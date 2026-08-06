# OMAKASE — Automated First-Pass Analysis for Finished Sequencing Orders

**Overall system configuration — for team discussion.**
Codename **OMAKASE** ("chef's choice": the facility proposes the analysis; the customer
does not have to order it).

| | |
|---|---|
| Version | v0.3 — 2026-07-31 |
| Status | Configuration sketch. **No implementation design yet.** |
| Purpose | Agree the layer boundaries first, then design each layer with the team. |

## What changed in v0.3 (review feedback incorporated)

| Topic | v0.2 said | v0.3 says |
|-------|-----------|-----------|
| **L0** | A consent gate with three levels (C0/C1/C2), including an institutional-cloud path | **No consent dialog.** Data minimisation instead: a fixed allow-list of non-sensitive order parameters, the **local vLLM only**, and a plain notice to the customer — *"Experiment parameters will be processed by a local AI model."* |
| **L1 trigger** | Poll the SUSHI DB for a new dataset carrying `order_id` | **Poll the B-Fabric DB.** Open item: confirm with Falko how B-Fabric signals that new data has become available in gStore. |
| **Naming** | "New SUSHI backend" | **"SUSHI backend"** / **"REST API"**. Nothing on the SUSHI side was invented for this. |
| **Validation** | Back-test the recipe engine against 12 months of historic jobs | **Dropped as an oracle.** Historic datasets often lack metadata, and older analyses used workflows now considered outdated. Replaced by: a metadata-readiness audit, recipes authored by bioinformaticians as current best practice, and forward shadow-mode on new orders. |
| **Metadata quality** | not addressed | Recognised as the real precondition. Simon has already been asked for more accurate B-Fabric order metadata (e.g. ready-made library sequencing is often filed as Sequencing Application "Custom/Other", which is useless). |

---

## 0. The five decisions in this document

| # | Decision | One-line reason |
|---|----------|-----------------|
| **D1** | **No consent dialog. Data minimisation instead.** Only allow-listed, non-sensitive order parameters are read, and only the on-prem vLLM is used. The customer is informed, not asked. | If nothing sensitive ever leaves the field allow-list, and inference stays on-prem, there is nothing to obtain consent for. Simpler, and safer than a consent form nobody reads. |
| **D2** | **A versioned recipe catalog decides the analysis. The LLM only assists.** | A rule can be reviewed, unit-tested and signed off by a bioinformatician. A prompt cannot. |
| **D3** | **QC is deterministic first; the LLM writes the verdict text.** | Reuses the existing SUSHI-MCP-server `loop_validation` discipline: the acting LLM's self-report is never evidence. |
| **D4** | **The always-on part is plain code, not an LLM.** | Removes the "keep an agent alive" problem. LLMs and the skill-aware harness are invoked per event. |
| **D5** | **4 hours = 4 *business* hours, armed only after the notice is verified.** | A Friday-17:00 order must not auto-start at 21:00 with nobody able to veto. |

### 0.1 Why this shape — determinism is what makes the LLM safe

The design keeps the pipeline deterministic and hands the LLM only the minimum. That is
not conservatism for its own sake. It is the mechanism that buys reproducibility, and
reproducibility is what makes using an LLM here safe at all.

**Two axes, closed separately.** They are easy to conflate, and closing only one is not
enough.

| Axis | Question | Closed by |
|------|----------|-----------|
| **Data** | What may the AI **see**? | L0 field allow-list (§3) — non-sensitive order parameters and numeric metrics, nothing else |
| **Authority** | What may the AI **decide**? | D2 / D3 — nothing binding. Rules decide; the model assists |

Sending less data does not help if the model still decides what runs: the decision would
remain unreproducible. Conversely, a deterministic decision layer is not enough if the
payload leaks sensitive fields. Both axes are therefore closed independently.

**Who does what, concretely.** In the normal path the LLM makes no decision at all.

| Task | Decided by | LLM role | Tuned by |
|------|-----------|----------|----------|
| Which app chain runs | recipe match predicate | none | recipe YAML |
| Parameters (`refBuild`, cores, ram) | recipe + species→reference table | none | recipe YAML + reference policy |
| Several recipes match, or none | LLM picks **among existing recipe ids**; below the confidence threshold → `HELD` | constrained choice | catalog + threshold |
| Proposal wording | template + LLM | writes the sentence | prompt template |
| QC verdict | deterministic tiers (§7) | none — may only **downgrade** | `qc_spec`, versioned with the recipe |
| QC narrative | LLM | writes the sentence | prompt template |
| Diagnosis of a failure | LLM agent, started by a human | full agentic work | **Skills** (§8.3) |

**What determinism buys — reproducibility.** A run is reproducible when it can be
re-derived from its record. The record holds `recipe_id@version`, the resolved parameters,
the input dataset id, and the `qc_spec` hash. Re-running the recipe on the same order
yields the same jobs — no model, prompt, temperature or sampling seed is involved. A
model-chosen app-and-parameter set would require pinning the model version, the prompt,
the decoding parameters and the seed, and providers retire models regardless.

**What reproducibility buys — safe LLM use.** Four properties, each a direct consequence:

1. **Bounded blast radius.** The worst an LLM error can do is pick the wrong recipe *among
   reviewed recipes* (caught by the veto window) or write a poor sentence (caught by the
   human release gate). It cannot invent an unreviewed pipeline, and it cannot emit an
   unresolved parameter — the API refuses that before submission.
2. **The model is not on the critical path.** If the on-prem model is unavailable, the rule
   engine still proposes. Availability of an LLM never gates the service.
3. **Behaviour change is reviewable.** Changing what runs is a diff in a versioned recipe
   with an author, not an edited prompt.
4. **Incidents are answerable.** "Why was this analysis run?" is answered with
   `recipe_id@version` and its author, not with "the model chose it".

**Failure modes this removes.** Each of these is concrete, not hypothetical:

* *Unresolved reference parameters reaching SLURM.* This actually happened: unresolved
  `ref_selector` values were passed through and polluted output rows across 13 of 16
  allow-listed apps until the `required_params` gate landed (`f3dfa9a`).
* *A confident-sounding but wrong QC pass.* Structurally impossible — the verdict is
  computed, and the model may only lower it.
* *Silent drift after a model or prompt change.* Decisions do not depend on the model, so a
  model upgrade cannot change which analysis an order receives.

**The honest limit.** Determinism does not make the *recipes* correct. It makes them
reviewable, testable and attributable. Correctness still comes from a bioinformatician
authoring the recipe and from Tier-3 QC comparing each run against the history of the same
recipe.

---

## 1. Layer model — the overall configuration

Seven layers. Each has one owner and one job.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ L0  DATA MINIMISATION       "what may the AI see at all?"                │
│     owner: field allow-list in code   → non-sensitive parameters only,   │
│                                         local vLLM only, user informed   │
├──────────────────────────────────────────────────────────────────────────┤
│ L1  TRIGGER                 "sequencing for order X is finished"         │
│     owner: omakase-core watcher       → polls the B-FABRIC DB            │
├──────────────────────────────────────────────────────────────────────────┤
│ L2  DECISION                "which analysis, with which parameters?"     │
│     owner: recipe catalog (YAML, versioned)   LLM = tie-break only       │
├──────────────────────────────────────────────────────────────────────────┤
│ L3  GATE                    "human veto window, then start"              │
│     owner: state machine + business-hours timer                          │
├──────────────────────────────────────────────────────────────────────────┤
│ L4  EXECUTION               "run it"                                     │
│     owner: SUSHI backend REST API → job_manager → SLURM → gStore         │
├──────────────────────────────────────────────────────────────────────────┤
│ L5  QC                      "is the result sane?"                        │
│     owner: deterministic checks (loop_validation)  LLM = narrative only  │
├──────────────────────────────────────────────────────────────────────────┤
│ L6  RELEASE                 "tell the customer"                          │
│     owner: bioinformatician (phase 1) → OMAKASE (phase 2, per recipe)    │
└──────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Which existing component plays which role

```
                    ┌───────────────────────────────────────────┐
   new data in      │           B-FABRIC  (SOAP)                │
   gStore           │  order · sample · run · workunit          │◄─── comments
   ─────────────────►│  ← polled for the trigger (L1)            │     (notification)
                     └──────────────┬────────────────────────────┘
                                    │ bfabricPy / btools
                                    ▼
   ┌────────────────────────────────────────────────────────────────────────┐
   │  ★ omakase-core   — the ONE new component (Python daemon, plain code)  │
   │                                                                        │
   │   watcher → field allow-list → recipe engine → timer → submitter       │
   │                    ▲                  ▲                    │           │
   │                    │                  │                    ▼           │
   │              QC gate ◄──── result collector ◄──────── job status       │
   │                                                                        │
   │   own state DB (SQLite → Postgres).  NO DDL on the SUSHI schema.       │
   └──┬─────────────┬──────────────────────────┬────────────────┬───────────┘
      │ REST+token  │ typed LLM call           │ MCP tools      │ read
      ▼             ▼                          ▼                │
 ┌───────────┐ ┌──────────────────────┐ ┌────────────────────┐  │
 │ SUSHI     │ │ SUSHI-MCP-server     │ │ SUSHI-MCP-server   │  │
 │ backend   │ │ llm_client           │ │ (MCP)              │  │
 │ REST API  │ │  └ local → FGCZ vLLM │ │  omakase_* tools   │  │
 │  /jobs    │ │    (the only channel)│ │  skills + provenance│ │
 └─────┬─────┘ └──────────────────────┘ └────────────────────┘  │
       │                                                         │
       ▼                     ┌─────────────────────────────┐     │
 ┌───────────┐  ┌────────┐   │  AI triage agent            │     │
 │job_manager│─►│ SLURM  │──►│  (failure diagnosis ONLY,   │     │
 │ (existing)│  └────────┘   │   started by a human)       │     │
 └───────────┘       │       └─────────────────────────────┘     │
                     ▼                                            │
              ┌──────────────────────────────────────────────┐   │
              │ gStore  /srv/gstore/projects/...             │───┘
              └──────────────────────────────────────────────┘

  ★ = new.  Everything else already exists and is reused unchanged.
```

**Only one new component is built:** the `omakase-core` daemon. Dropping the consent
dialog also removed the second new item that v0.2 needed (a consent field in B-Fabric).

---

## 2. Verified facts this rests on

Checked in the repo / on this host, not assumed.

| Fact | Source |
|------|--------|
| bfabricPy is installed (`gi_py3.12.8`); entities `order`, `sample`, `run`, `workunit`, `dataset`, `project`; generic `bf.read()` / `bf.save(endpoint, obj)` | `bfabric/entities/*.py` |
| `order → project` resolution already implemented | `btools/get_project_id_from_order.py` |
| The SUSHI backend can submit jobs over HTTP; `job_manager` picks them up → SLURM (verified end-to-end on 083) | L1 `new_sushi_backend_api` |
| 16 legacy apps + native Fastqc run head-lessly (`LEGACY_APPS_ALLOWLIST`) | same, §4.1 |
| A `required_params` gate now blocks unresolved `ref_selector` params | main `f3dfa9a` |
| **`llm_client` already has a `local` provider (OpenAI-compatible → the FGCZ vLLM)** and supports schema-constrained output (`output_schema`) | `skillsets/llm_client/config/llm_client.yml`, `lib/llm_client/openai_adapter.rb:36` |
| **`loop_validation` already defines**: evidence spec declared before the run, fail-closed mechanical verdict, spec pinned by sha256, outcome recorded as an attestation | `knowledge/loop_validation/loop_validation.md` |
| SUSHI datasets carry `order_id` (indexed) — still useful for linking, no longer the trigger | `legacy_sushi/master/db/schema.rb:47,50` |
| fgcz-h-083 has **no cron and no cron daemon** | prior session finding |
| The SUSHI backend instance on the production node fgcz-h-082 is **`SUSHI_READ_ONLY=1`** today | prior session decision |
| FGCZ AI policy: the on-prem vLLM covers up to `confidential` and is the only channel permitted for personal data | `ai-usage-policy` skill |

---

## 3. Layer 0 — data minimisation instead of consent

### 3.1 The approach

Do not ask for permission to process sensitive data. **Never read it in the first place.**

```
  B-Fabric order record                 field allow-list                 destination
  ─────────────────────                 ────────────────                 ───────────
  Service Type              ──────────►  Service Type            ───────►  FGCZ local vLLM
  Sequencing Application    ──────────►  Sequencing Application            (on-prem, nothing
  Species                   ──────────►  Species                            leaves the network)
  Instrument                ──────────►  Instrument
  Library Protocol          ──────────►  Library Protocol
  sample count / layout     ──────────►  sample count / layout
  ─────────────────────────────────────────────────────────────
  customer name             ╳ never read
  contact details           ╳ never read
  project title             ╳ never read
  sample names              ╳ never read
  free-text comments        ╳ never read
```

Three rules:

1. **Allow-list, not redaction.** The daemon reads only the listed fields. A field that is
   not on the list is never fetched, so it cannot leak through a bug in a scrubber.
2. **Local vLLM only.** No institutional cloud path, no hosted API. This removes the whole
   "which tool is approved for which classification" matrix from the design.
3. **Raw data and free-text logs never reach the LLM.** QC sends **numeric metrics only**.
   A log excerpt can contain project paths and sample names, so log text is excluded — the
   deterministic QC tiers work on numbers anyway.

### 3.2 What the customer is told

No dialog, no checkbox. A plain statement, in the order confirmation and/or the result
notification:

> *"Experiment parameters will be processed by a local AI model."*

Wording and placement to be confirmed with whoever owns customer-facing text.

### 3.3 The one caveat to keep in view

Data minimisation removes the consent question **only while the payload stays inside the
allow-list.** If someone later wants to send free-text logs, sample sheets, or result
tables to the model, the question comes back. So the allow-list must be enforced in code
and reviewed when it changes — it is a security boundary, not a convention.

---

## 4. Layer 1 — trigger: poll the B-Fabric DB

**Decision: poll B-Fabric.** The business event lives there, so that is where we watch.

```
   B-Fabric DB  ──poll every 5–15 min──►  "new data available in gStore for order X"
                                                      │
                                                      ▼
                                          omakase-core creates a candidate
```

**Open item (Falko):** what exactly can we read from B-Fabric to learn that new data has
become available in gStore? Candidates to confirm: order status, run status, workunit
status, or a resource/dataset registration event. We need the field, its values, and the
latency between "files are in gStore" and "B-Fabric shows it".

Notes:

* Whatever the signal is, the daemon must confirm the files are actually readable in
  gStore before proposing anything. A status flag is a hint; the filesystem is the truth.
* `data_sets.order_id` in SUSHI stays useful for linking a later analysis back to the
  order. It is no longer the trigger.
* **Scheduling caveat:** 083 has no cron. Use a systemd user timer or a supervised loop.
  Production needs a proper service host with systemd (sysadmin dependency).

---

## 5. Layer 2 — decision: a recipe catalog

### 5.1 Example recipe

```yaml
# recipes/bulk_rnaseq_illumina_v3.yaml
id: bulk_rnaseq_illumina
version: 3
author: <bioinformatician>          # current best practice, signed off by a human

match:                              # deterministic predicate over allow-listed fields
  service_type:            [ ... ]
  sequencing_application:  [RNA-Seq, Quant-Seq]
  instrument:              [Illumina]
  library_protocol:        [ ... ]
  species_in_reference_catalog: true
  samples: { min: 2, max: 96 }

steps:                              # apps MUST be in LEGACY_APPS_ALLOWLIST
  - app: FastqcApp
  - app: STAR
    params: { refBuild: "{{ reference_for(species) }}", cores: 8, ram: 40 }
  - app: FeatureCounts
    params: { refBuild: "{{ same_as_previous }}" }
  - app: CountQC
    when: has_factor_column
  - app: DESeq2
    when: has_factor_column and n_groups >= 2 and min_replicates >= 2

qc_spec: specs/bulk_rnaseq_v3.json  # the evidence spec (§7)
budget:  { max_core_hours: 200 }
autostart: true                     # false ⇒ always HELD, human must press GO
```

### 5.2 Why a recipe and not a prompt

| Property | Recipe | Free-form LLM |
|---|---|---|
| Reproducible from the record | `recipe_id@version` + resolved params | prompt + model + temperature + luck |
| Reviewable | a diff in git | a prompt edit |
| Signed off by a domain expert | yes, per recipe | no |
| Auditable after an incident | yes | "the model chose it" |

`refBuild` resolution is not cosmetic. Unresolved `ref_selector` params were reaching
SLURM and polluting output rows until the `required_params` gate landed (`f3dfa9a`;
13/16 allow-listed apps affected). Every proposal must be pre-validated against
`GET /api/v1/application_configs/<app>` before it is shown to anyone.

### 5.3 Where the recipes come from — **not** from history

v0.2 proposed back-testing the recipe engine against 12 months of historic SUSHI jobs.
**That is dropped.** Two reasons, both decisive:

* Historic SUSHI datasets often **lack the metadata** the match predicate needs.
* Older analyses used **workflows now considered outdated**, which should not be run again.
  A back-test would therefore measure agreement with something we do not want to reproduce.

So the catalog is authored forward, not derived backward:

```
  bioinformaticians write the recipe for each top order type   (current best practice)
                              │
                              ▼
  shadow mode on NEW orders — propose, write nothing, compare with what is actually run
                              │
                              ▼
  the recipe is corrected until the bioinformatician is satisfied, then whitelisted
```

The recipe catalog is thus valuable in its own right: it is the first machine-readable
record of current best practice per order type.

---

## 6. Layer 4 — execution

One hard rule: **OMAKASE never writes the SUSHI database directly.**

```
omakase-core ──HTTP + project-scoped token──► SUSHI backend  POST /api/v1/jobs
                                                      │
                                                      ▼
                                          Job rows (status CREATED)
                                                      │
                                          job_manager (existing) → sbatch
```

Nothing here is new on the SUSHI side. The REST API, `job_manager` and SLURM path already
exist and are used unchanged. What we get for free: project-scope enforcement from the
token, the `required_params` gate, SAMPLE-mode fan-out, legacy-parity output columns, and
no code path by which the orchestrator could corrupt the shared production database.

---

## 7. Layer 5 — QC, as `loop_validation` applied to analysis results

The existing SUSHI-MCP-server verification discipline already states what we need:

> The acting LLM's self-report is never evidence. A verdict consumes only mechanically
> observable results, and absence of evidence never defaults to a pass.

So the QC gate **is** an instance of it. Reuse the format and the engine.

```
recipe.qc_spec  (declared BEFORE the run, pinned by sha256)
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│ Tier 1  structural   exit code · expected files exist & non-  │
│                      empty · dataset.tsv parses · row count = │
│                      sample count · no OOM · runtime sanity   │
│ Tier 2  domain       %uniquely-mapped · %rRNA · library size ·│
│                      #genes · duplication · 10x barcode knee  │
│ Tier 3  historical   z-score vs the last N runs of THIS recipe│
└───────────────┬───────────────────────────────────────────────┘
                │ mechanical, fail-closed
                ▼
        PASS / WARN / FAIL   ──►  recorded with the spec hash
                │
                ▼
        LLM writes the narrative, from the NUMBERS only.
        It may DOWNGRADE a verdict. It may never upgrade a FAIL.
```

Tier 3 is what catches "the pipeline succeeded but the data is wrong".
Failure triage reuses the existing known-error tooling.

---

## 8. The LLM: one channel, two runtimes

### 8.1 Channel — on-prem only

| Channel | `llm_client` provider | Used here? |
|---------|----------------------|-----------|
| **FGCZ vLLM (on-prem, free)** | `local` (OpenAI-compatible `base_url`) | **yes — the only one** |
| UZH Copilot CLI (institutional) | `copilot` | no |
| Anthropic hosted API | `anthropic` | no |

Because the channel is fixed and the payload is allow-listed, the guard in front of
`llm_client` is small: *is every field on the allow-list, and is the endpoint the local
one?* Refuse otherwise, and log it.

### 8.2 Runtime — a typed call for the pipeline, a harness for triage

| Task | Shape | Needs the skill-aware harness? |
|------|-------|-------------------------------|
| Recipe tie-break on an ambiguous order | 1 call, JSON schema out, no tools | no — the recipe catalog *is* the knowledge |
| Proposal comment text | 1 call, no tools | no |
| QC verdict narrative (from metrics) | 1 call, no tools | no |
| **Diagnosis of a failed analysis** | consult known errors and app guides, read logs, check gStore and SLURM; open-ended, multi-step, tool-using | **yes** |

For the first three, `llm_client` alone is enough: one request, schema-validated JSON, no
loop, no state, and a crash is just a retry.

For the fourth, a harness that runs against our own skills and tools genuinely earns its
place. Rebuilding skill retrieval, tool mediation with write-gates, and output provenance
in plain code would be months of work for no benefit. That is why SUSHI-MCP-server is
named here — not preference, but the fact that those parts already run.

Two boundaries to keep:

* The harness is a **library invoked per event**, not an always-on autonomous agent (D4).
* The seam should be **coarse**: "diagnose this failure, return a structured report" —
  one call, not fine-grained tool driving from the daemon. A single boundary is easy to
  replace later.

### 8.3 How Skills are used

A **Skill** here means a curated, versioned unit of instruction and knowledge that an agent
loads at run time from SUSHI-MCP-server. Skills are the natural place to encode *how the AI
should investigate and explain*. They are the wrong place to encode *what gets run*.

**The boundary rule**

> Skills tune how the AI investigates and words things. They never change which analysis
> runs, and they never change a QC threshold.

| What is being tuned | Tuned by | Deliberately **not** by |
|---------------------|----------|-------------------------|
| Which analysis an order receives | recipe YAML — reviewed, authored, signed off | a Skill |
| QC thresholds and checks | `qc_spec`, versioned with the recipe | a Skill |
| How a failure is diagnosed | **Skills** — known-error catalog, app developer guides, debug procedures | — |
| How findings are worded | prompt templates | — |
| What data may be sent where | the L0 allow-list in code, plus the AI-usage policy substrate | a Skill alone |

**Where Skills genuinely earn their place**

1. **Failure triage** (§8.2 tier 2). The agent loads the known-error catalog, the relevant
   app's developer guide and the debug procedure, then reads logs, checks gStore and queries
   SLURM. This is open-ended, tool-using work; a Skill is exactly the right container for
   the procedure. Its output is a *proposal to a human*, never an action.
2. **The verification discipline itself.** `loop_validation` is a Skill that governs the
   agent rather than instructing it: declare the evidence spec before the run, compute a
   fail-closed verdict from mechanical results, record it with the spec hash. OMAKASE's QC
   gate is an instance of it (§7), which is why we do not build a second QC framework.
3. **Institutional guardrails as substrate.** The FGCZ AI-usage policy — what data may go
   to which tool — is loaded as a Skill, so every agent inherits it instead of re-deriving
   it. L0 still enforces the rule in code; the Skill makes the rule legible to the agent.
4. **The operator surface.** The `omakase_*` tools plus their usage notes form the Skill a
   bioinformatician (or an agent acting on their behalf) uses to inspect, veto, override and
   release. This is how phase 1 works with no user interface.
5. **Tuning without redeployment.** Improving triage quality means editing a Skill, not
   changing the daemon. The deterministic core stays untouched, which is precisely why this
   kind of iteration is safe.

**The anti-pattern to avoid**

Encoding an analysis choice in a Skill — for example, "for RNA-seq use STAR then
FeatureCounts". It would work, and it would quietly undo D2: behaviour would then depend on
which Skill version an agent happened to load, and the run record would no longer explain
itself. Analysis choices live in recipes, which are versioned, reviewed and cited on every
run.

**One honest caveat.** A Skill is a prompt with provenance. It improves consistency and
makes the agent's behaviour attributable; it does not turn the agent's conclusions into
evidence. That is why triage output is advisory, and why the mechanical verdict of
`loop_validation` sits underneath it.

### 8.4 One shared LLM layer, not one per module

We already have more than one place that calls an LLM: the M&M module inside ezRun, and
method-description generation in SAKE. OMAKASE would be a third. If every module keeps its
own caller, maintenance cost grows with each one.

A shared **library** is not possible here — ezRun is R, SUSHI-MCP-server is Ruby,
`omakase-core` would be Python. So the only thing that can actually be shared is a
**service**. Agreeing on one service, and having the modules call it, is the decision worth
making now rather than after the third implementation exists.

---

## 9. Layer 6 — human in the loop

Phase 1 needs veto / override / release **before any UI exists**. Three channels:

| # | Channel | Status |
|---|---------|--------|
| 1 | **B-Fabric internal comment** — the channel the original idea asks for | ⚠ open: can a comment be staff-only? |
| 2 | **Email digest** to the bioinformatics group, with deadline and links | always works, gives a paper trail |
| 3 | **SUSHI-MCP-server MCP tools** — works from the CLI on day 1 | reuses existing infrastructure |

```
omakase_pending           # proposals awaiting response + deadline countdown
omakase_show <id>         # parameters, recipe, resolved params, cost estimate
omakase_veto <id> --reason
omakase_override <id> --recipe <id@v> | --app ... --params '{...}'
omakase_hold <id>         # stop the clock
omakase_go <id>           # release a HELD proposal
omakase_qc <id>           # QC report
omakase_triage <id>       # start the AI triage agent on a failure  (§8.2)
omakase_release <id>      # phase 1: approve the customer-visible comment
omakase_pause / _resume   # global kill switch
```

Every action is logged with actor and timestamp.

### 9.1 A chat surface — Slack / Teams as the operator's secretary

The three channels above cover "can a human act at all". A chat bot answers a different
question: **will a human notice in time?** That is the weakest point of the whole gate. An
unread B-Fabric comment or a filtered digest mail makes the veto window ceremonial.

A bot is a good fit here precisely because it decides nothing. It reports state that the
state machine already holds, and it relays actions into the same audited transitions.

**What it does — the secretary functions**

| When | What it posts |
|------|---------------|
| Every morning | Proposals awaiting a response with their deadline countdown; jobs that finished or failed since yesterday; QC `WARN` / `FAIL` waiting for review |
| On a new proposal | Order, recipe, resolved parameters, cost estimate, deadline — with *veto* / *hold* affordances |
| One hour before a deadline | A reminder naming the person expected to act |
| On failure or QC `FAIL` | The job, its state, and the diagnosis if triage has run |
| On demand | "status of order X", "what is pending for p35611", "why did job 581 fail" |

Schedule awareness falls out for free: the daemon already computes business-hours
deadlines, so the bot can say *"two proposals expire before 18:00 today"*.

Each alert becomes a **thread**, and the thread is the working context: a veto reason typed
in the thread is the reason recorded in the transition log.

**Two tiers, and the boundary is the governance boundary**

```
Tier A — proactive, deterministic          Tier B — reactive, agentic
digests · alerts · deadline reminders      free-text questions in a thread
plain code: query state → format → post    Hermes + Skills, one task per message
no LLM involved                            reads logs, gStore, SLURM, known errors
runs unattended (it is just a cron job)    ATTENDED by construction
```

The second column is the interesting part. Hermes has been blocked from unattended
operation by the governance track (§8.2). **A chat message is a human-initiated
invocation** — someone typed it, and they are watching the thread for the answer. So the
conversational tier is attended *by construction*, which makes a chat surface the cheapest
legitimate way to put an agentic body into daily use under the current rules. The part that
genuinely runs unattended — the digests and alerts — needs no agent at all.

**Constraints that must be respected**

1. **Slack and Teams are external cloud services.** This is the same classification
   question as the LLM channel, but about transport rather than inference. Teams under the
   institutional M365 tenancy is the safer default; Slack needs a policy check before any
   FGCZ content goes into it. Either way the bot inherits the L0 discipline: post
   identifiers, states, counts and deadlines — **not** sample names, customer names,
   project titles or result content. A link back to B-Fabric or SUSHI carries the detail.
2. **Write actions are an authorisation surface.** A chat identity must be mapped to an
   LDAP login before it can act. Recommended split for phase 1: *read*, *veto* and *hold*
   from chat; *override* and *release to the customer* from the CLI, or from chat only with
   an explicit confirmation step. Releasing a result to a customer from a chat tap is a
   bigger step than stopping a job.
3. **The bot is never the source of truth.** It reads OMAKASE state through the same API
   the CLI uses, and every action it relays lands in the `transitions` table with the
   resolved LDAP actor — not "slack-bot".
4. **Alert fatigue is the failure mode.** One post per state transition, digests instead of
   per-event mail, per-person routing, and no re-posting. If the response rate to bot
   messages drops, the gate is theatre again — so response rate is worth tracking as a
   health metric.

**Suggested build order.** An outgoing webhook that posts the morning digest is roughly a
day of work, has no inbound surface and no auth surface, and already delivers most of the
value. Interactive buttons, then the conversational tier, come after — and only once the
identity mapping exists.

---

## 10. State machine

One row per candidate = (order_id, input_dataset_id, recipe_id, recipe_version).

```
              ┌──────────┐
   watcher ──►│ DETECTED │   (B-Fabric says new data is available)
              └────┬─────┘
                   │  read allow-listed parameters + verify files in gStore
              ┌────▼────────┐
              │ PARAMS_OK   │──► SKIPPED   (ineligible / parameters unusable)
              └────┬────────┘
                   │  recipe engine  (+ LLM tie-break if ambiguous)
            ┌──────▼──────┐
            │  PROPOSED   │   notice posted & read back → deadline armed
            └──┬───┬───┬──┘
     veto  ◄───┘   │   └───► OVERRIDDEN ──┐
   CANCELLED       │                       │
                   │  low confidence /     ├──► APPROVED ──► SUBMITTED ──► RUNNING
                   │  not whitelisted /    │                                  │
                   │  budget exceeded      │                    ┌─────────────┴──────┐
                   └──► HELD ──(human GO)──┘                 all OK              any FAILED
                                                                │                    │
                                                          ┌─────▼────┐         ┌─────▼────┐
                                                          │  QC_RUN  │         │  FAILED  │
                                                          └─────┬────┘         └─────┬────┘
                                            ┌───────────────────┼──────────┐         │
                                       PASS │              WARN │     FAIL │    omakase_triage
                                  ┌─────────▼────────┐  ┌───────▼────┐ ┌───▼───────┐
                                  │ RELEASE_PENDING  │  │ REVIEW_REQ │ │ QC_FAILED │
                                  └─────────┬────────┘  └───────┬────┘ └───────────┘
                                            │                   │
                                            └────────►  RELEASED ◄──── (phase 1: human
                                                                        approves the text;
                                                                        phase 2: OMAKASE
                                                                        posts it directly)
```

Invariants:

* Transitions are append-only: timestamp, actor, reason.
* Idempotency key = (order, input dataset, recipe@version). Re-detection is a no-op.
* Crash-safe: state is re-derived from the OMAKASE DB + SUSHI job status, never memory.
* **`PROPOSED → APPROVED` is the only time-based transition in the entire system.**

---

## 11. Safety rails

| Rail | Rule |
|------|------|
| Field allow-list | enforced in code; a change to it is a reviewed change |
| On-prem only | the LLM endpoint is pinned; any other target is refused |
| No free-text to the model | metrics and allow-listed parameters only; never logs, sheets or result tables |
| Global kill switch | `omakase_pause`: keep observing, stop all writes and submissions |
| Opt-out | per project, per customer, per recipe (`autostart: false`) |
| Whitelist not blacklist | phase 1 runs only for explicitly enabled (project × recipe) pairs |
| Compute budget | per-recipe core-hour cap, global daily cap, max concurrent auto-jobs; exceeded ⇒ HELD |
| Low-priority QoS | auto jobs must never delay customer-ordered work |
| Business-hours deadline | 4 working hours, 08:00–18:00 Mon–Fri, floor = next working day 10:00 |
| Deadline armed after verified notice | post → read back → *then* start the clock |
| No auto-retry of failures | a failure notifies a human; silent retries hide real problems |
| Idempotent, tagged B-Fabric writes | comments carry `[omakase:<state>:<id>]`; never double-post |
| AI transparency | the customer is told that experiment parameters are processed by a local AI model; phase-2 comments say they are AI-drafted and human-supervised |
| Dry-run forever | `OMAKASE_DRY_RUN=1`: full pipeline, no writes, no submissions |

---

## 12. Data model (OMAKASE-owned, not SUSHI)

```
candidates(id, order_id, project_number, input_dataset_id,
           recipe_id, recipe_version, state, confidence,
           autostart, deadline_at, created_at, updated_at,
           UNIQUE(order_id, input_dataset_id, recipe_id, recipe_version))

order_params(id, candidate_id, field, value)     -- ONLY allow-listed fields
proposal_steps(id, candidate_id, seq, app_name, params_json, depends_on_seq)
transitions(id, candidate_id, from_state, to_state, actor, reason, payload_json, at)
notifications(id, candidate_id, channel, target, external_ref, tag, posted_at, verified_at)
submissions(id, candidate_id, step_seq, sushi_job_ids_json, output_dataset_id, submitted_at)
qc_results(id, candidate_id, tier, metric, value, threshold, verdict, spec_sha256, at)
llm_calls(id, candidate_id, purpose, endpoint, model, payload_fields, prompt_sha256,
          response_json, at)
```

`order_params` is the audit trail for L0: it shows exactly which fields were read.
`llm_calls.payload_fields` records which allow-listed fields were sent, so an audit can
prove that nothing outside the list ever reached the model.

---

## 13. Phases

```
 PHASE 0 — SHADOW  (start immediately, zero risk)
   Detect → propose → QC.  Write NOTHING anywhere.
   In parallel: the metadata-readiness audit (§17) and recipe authoring.
   EXIT: metadata sufficiency measured per service type; recipes for the top order
         types signed off by bioinformaticians; proposals on NEW orders match what
         was actually run, in the bioinformaticians' judgement; on-prem LLM path
         verified end to end.

 PHASE 1 — HUMAN-GATED   ← the original idea's phase 1
   Internal notice only.  Auto-start after the business-hours deadline,
   restricted to whitelisted (project × recipe).  Release needs a human.
   Nothing customer-visible is ever written by the AI.
   EXIT (per recipe): ≥50 auto-started runs; ≥95 % released with no change of app or
         parameters; zero wrong-reference/species/design deliveries; measurable
         reduction in bioinformatician handling time.

 PHASE 2 — AI WRITES TO THE CUSTOMER
   Per recipe, only after phase-1 exit criteria, with sign-off.
   Comment is AI-drafted and labelled.  WARN / FAIL / HELD still go to a human.
   Kill switch and opt-out stay forever.
```

Promote a recipe because its own counters say so — not because the system feels reliable.

---

## 14. Prerequisites

| # | Prerequisite | Status | Blocks |
|---|--------------|--------|--------|
| P1 | **Better B-Fabric order metadata** — the match predicate needs usable Service Type / Sequencing Application / Species / Instrument / Library Protocol. "Custom/Other" for ready-made library sequencing is useless. | Simon already approached | recipe matching for the affected order types |
| P2 | **The B-Fabric → gStore availability signal** (Falko): which field/event tells us new data is there, and with what latency | open | the trigger (L1) |
| P3 | **Customer-facing notice wording** — "Experiment parameters will be processed by a local AI model" | to confirm with the owner of customer text | phase 1 |
| P4 | **SUSHI backend write path on the production node 082** (pin `SECRET_KEY_BASE`, scoped token, drop `SUSHI_READ_ONLY`, confirm the production `job_manager` picks up the rows) | 082 read-only; pickup verified on 083 only | phase 1 on real orders |
| P5 | **FGCZ vLLM wiring for `llm_client`** (`local` provider + `base_url`) | adapter exists; not wired for this use | any LLM step |
| P6 | **B-Fabric service account** + comment mechanics (staff-only visibility?) | open | notification channel 1 |
| P7 | **Recipe coverage**: grow `LEGACY_APPS_ALLOWLIST` (10x / ONT / PacBio not yet head-lessly validated) | 16 apps + Fastqc | catalog breadth |
| P8 | **Service host with systemd** (not 082 — 15 GB, no swap, submit node; 083 has no cron) | to arrange | phase 1 |
| P9 | **Machine-readable reference-genome policy** per species | implicit in `ref_selector` | parameter resolution |
| P10 | *(triage only)* runtime and safety machinery to run the AI triage agent without a human | not in place | fully automatic triage — **not** phase 1 |
| P11 | **Chat-platform decision and policy check** (§9.1): Teams under the institutional tenancy, or Slack? What may be posted there? | open | the chat surface |
| P12 | **Chat identity → LDAP mapping** before any action can be taken from a thread | open | write actions from chat (read-only digests need none) |

---

## 15. Risks

| Risk | Mitigation |
|------|-----------|
| Metadata too poor to match a recipe | measured first (§17); order types below the bar simply stay out of scope until the B-Fabric fields improve |
| Wrong analysis delivered (wrong reference / species / design) | recipe reviewed by a bioinformatician + `required_params` gate + Tier-2 species checks + human release gate |
| Timer fires when nobody is reachable | business-hours deadline; armed only after verified notice; whitelist |
| Cluster flooded by first-pass analyses | budget caps, concurrency cap, low-priority QoS |
| Sensitive data reaches the model | allow-list enforced in code; on-prem endpoint pinned; `llm_calls.payload_fields` audit |
| Allow-list widened quietly over time | it is a security boundary: changes are reviewed (§3.3) |
| B-Fabric comment spam → the gate becomes theatre | one comment per transition, tagged; digest email; track response rate |
| Another LLM caller added per module | agree on one shared service now (§8.3) |
| Scope creep into "AI runs the facility" | D2 + D3: code decides, the LLM explains |

---

## 16. Open questions and action items

**B-Fabric — Falko**

* How can we learn from B-Fabric that new data has become available in gStore? Which
  field or event, which values, and what is the latency?
* Can a comment be visible to FGCZ staff only, and on which entity (order / container /
  workunit)? The shape of the phase-1 gate depends on this.
* Is there a service account we may use for reading order parameters and writing comments?

**B-Fabric metadata — Simon (in progress)**

* More accurate order metadata: Service Type, Sequencing Application, Species,
  Instrument, Library Protocol. Ready-made library sequencing filed as
  Sequencing Application "Custom/Other" cannot drive any decision.
* Which fields can realistically become mandatory, and from when?

**Customer communication**

* Wording and placement of the notice: *"Experiment parameters will be processed by a
  local AI model."* Who owns and signs off that text?
* Must a phase-2 customer-facing comment state that it is AI-drafted? (My reading of the
  UZH/ETH transparency rules: yes.)

**Operations**

* Confirm "4 hours" means business hours, including weekends and holidays.
* Pilot scope: which order types first? Which projects volunteer?
* Who pays for first-pass compute; monthly core-hour cap; is a low-priority SLURM QoS
  available so auto jobs never delay customer-ordered work?
* What does "forward the result to the user" mean concretely — the existing workunit and
  gStore link, or a generated report?
* **Chat surface (§9.1):** Teams or Slack? Is either approved for FGCZ `internal` content?
  Who maps chat identities to LDAP logins? Which actions may be taken from a thread?

**Architecture**

* Agreed that the always-on layer is plain code, with the LLM and the harness invoked per
  event? (D4)
* Agreed that the AI triage agent is started by a human only in phase 1? (§8.2)
* Agreed that we start **without** a consent dialog — allow-listed parameters, on-prem
  model, and a plain notice to the customer? (D1)
* Agreed to standardise on **one** LLM service for ezRun / SAKE / OMAKASE? (§8.4)
* Agreed that Skills tune diagnosis and wording, never which analysis runs? (§8.3)
* Agreed that the chat bot starts as post-only digests, with actions added only after the
  identity mapping exists? (§9.1)

---

## 17. Suggested first step

Three things, none of which touch production.

```
1.  METADATA-READINESS AUDIT   (read-only, B-Fabric orders, recent months)
    For each order: are Service Type / Sequencing Application / Species /
    Instrument / Library Protocol present and usable?
    How often is the value "Custom/Other" or empty?  Report per service type.
    → this is also the evidence for the metadata request already made to Simon.

2.  RECIPES FOR THE TOP ORDER TYPES
    Written by bioinformaticians as current best practice — not derived from
    historic jobs, which used workflows we no longer want to run.
    Start with the highest-volume type (bulk Illumina RNA-seq is the obvious one).

3.  SHADOW MODE ON NEW ORDERS
    Propose, write nothing, and let the bioinformaticians compare the proposal
    with what they actually ran.  This is the real validation, and it is forward
    looking, so it cannot be poisoned by outdated history.
```

Step 1 tells us how much of the order flow is even addressable today. Step 2 produces the
first machine-readable record of current best practice. Step 3 is the honest test.
