# OMAKASE — session handoff

Written 2026-08-03, updated 2026-08-06 and 2026-08-21. Read this first when resuming in a
new session. L2 record: `handoff_omakase_20260821_species_measured_step2_is_next` (detail
in `omakase_20260821_species_measured_hermes_scope_clarified`; earlier records
`omakase_auto_analysis_v04_handoff_20260803`,
`omakase_auto_analysis_v03_docs_slides_pptx_20260803`,
`omakase_auto_analysis_design_20260731`).

> **State as of 2026-08-21.** §17 step 1 is done: both audits ran against production,
> read-only, no model call. Nothing is blocked on a decision. What remains is step 2 —
> a bioinformatician writing the recipes. The measurements are in the design's §2, what
> they change is in §3.2a and §5.1, and the illustrated summary is
> `docs/omakase-status-report-20260821-{ja,en}.html`. Section 6 of this file
> (open items) is still accurate apart from the Simon entry, which is now a written
> request in draft.

---

## 1. What OMAKASE is

A configuration proposal for **automated first-pass analysis of finished sequencing
orders** at FGCZ. Origin: a colleague's request — when sequencing finishes, an agent reads
the order meta-information, proposes an analysis, notifies the bioinformatician, starts the
analysis if nobody replies within a grace period, then an AI checks the result and a human
forwards it to the customer. Phase 1 gates everything through a bioinformatician; phase 2
lets the AI write customer-facing comments.

**Status: no OMAKASE implementation exists.** The design is complete, and §17 step 1 (the
metadata audits) is done — but those scripts are read-only measurement tools, not the
system. Nothing polls, proposes, gates or runs anything yet.

---

## 2. Files (all in `/srv/sushi/masa_test_new_sushi_20260527`)

| Path | Size | Role |
|------|------|------|
| `docs/omakase-auto-analysis-design.md` | 50 KB | **Source of truth.** EN, v0.3, sections 0–17 |
| `docs/omakase-auto-analysis-overview-ja.html` | 58 KB | Illustrated, JA, 14 figures + annex |
| `docs/omakase-auto-analysis-overview-en.html` | 54 KB | Illustrated, EN, same 14 figures |
| `docs/presentations/omakase_auto_analysis_ja.html` | 45 KB | Deck, JA, 14 slides |
| `docs/presentations/omakase_auto_analysis_en.html` | 43 KB | Deck, EN, 14 slides |
| `docs/presentations/omakase_auto_analysis_{ja,en}.pptx` | ~67 KB | Editable PowerPoint, generated |
| `docs/presentations/deck_to_pptx.py` | 31 KB | Deck HTML → pptx converter |
| `docs/omakase-status-report-20260821-{ja,en}.html` | ~40 KB | **Status report**, 6 figures, JA+EN — where the system stands after the audits |
| `docs/omakase-bfabric-metadata-request.md` | 8 KB | The metadata request with the numbers attached. **Draft, not sent** |
| `scripts/omakase_metadata_audit/` | — | §17 step 1: the order-side audit (read-only, no LLM) |
| `scripts/omakase_species_audit/` | — | Where Species comes from and what it resolves to (read-only, no LLM) |
| `scripts/html_artifact_check/` | — | Mechanical gate for these HTML artifacts; there is no browser on these nodes |
| `docs/omakase-HANDOFF.md` | this file | |

> **Committed on 2026-08-06** (`97221ea`, local `main`, not pushed). They were untracked
> until then, in a working tree shared with other Claude sessions — 12 untracked files were
> destroyed once before by a parallel session. Keep new artifacts committed as they land.

---

## 3. The design in one page

Seven layers, one owner each:

| Layer | Job | Owner |
|-------|-----|-------|
| L0 | **Data minimisation** — what may the AI see? | field allow-list in code |
| L1 | **Trigger** — sequencing for order X finished | `omakase-core` watcher polls the **B-Fabric DB** |
| L2 | **Decision** — which analysis, which parameters | versioned **recipe catalog**; LLM breaks ties only |
| L3 | **Gate** — human veto window, then start | state machine + business-hours timer |
| L4 | **Execution** | **SUSHI backend REST API** → job_manager → SLURM → gStore (all existing) |
| L5 | **QC** — is the result sane | deterministic tiers; LLM writes narrative only |
| L6 | **Release** | phase 1 bioinformatician, phase 2 per-recipe automation |

**Only one new component is built:** `omakase-core`, a Python daemon with its own state DB.
No DDL on the SUSHI schema. All SUSHI mutations go through the REST API.

Five decisions (D1–D5): no consent dialog (data minimisation instead) · recipe catalog
decides · QC deterministic first · the always-on part is plain code · 4 *business* hours,
clock armed only after the notice is read back.

Catchphrase: **Rules decide · AI assists · Humans release**

---

## 4. Version history and why things changed

* **v0.1/v0.2** — introduced the consent gate (C0/C1/C2), SUSHI-DB trigger, a 12-month
  back-test as validation, and an LLM-runtime section discussing Hermes.
* **v0.3** — five changes from real review feedback:
  1. **Consent → data minimisation.** Only allow-listed non-sensitive order fields
     (Service Type, Sequencing Application, Species, Instrument, Library Protocol, sample
     count/layout), local vLLM only, and a plain notice to the customer:
     *"Experiment parameters will be processed by a local AI model."* No dialog.
  2. **Trigger → poll the B-Fabric DB** (open item for Falko: which field/event says new
     data is in gStore).
  3. **Naming: never "New SUSHI backend"** — write "SUSHI backend" / "REST API". Nothing on
     the SUSHI side was invented for this.
  4. **Back-test dropped as an oracle** — historic datasets often lack metadata, and older
     analyses used workflows now considered outdated. Replaced by: metadata-readiness audit
     → recipes authored by bioinformaticians → shadow mode on NEW orders.
  5. **Metadata quality is the real precondition** — Simon already asked for better
     B-Fabric order fields ("Custom/Other" for ready-made library sequencing is useless).
* **Added later the same day** (first in the doc and slides): §0.1 determinism →
  reproducibility → safe LLM use; §8.3 how Skills are used; §9.1 a Slack / Teams chat
  surface. **The overview HTMLs caught up on 2026-08-06**: three figures added (determinism
  as Fig 4, Skills as Fig 6, the chat surface as Fig 11) and the rest renumbered, 11 → 14.
  All four artifacts now carry the same content.

Naming convention set by the user: `KairosChain` and `sushi-chain` are **always written
`SUSHI-MCP-server`** in every artifact. Internal jargon (Hermes, INV-*, ATTENDED, guard
track) was stripped from team-facing docs; the md keeps it in §8 as the reasoning record.

---

## 5. The three conceptual pieces added last

**§0.1 — determinism is the safety mechanism.** Two axes closed separately: *data* (what
the AI may see → allow-list) and *authority* (what the AI may decide → nothing binding).
Determinism buys reproducibility (a run re-derives from `recipe_id@version` + resolved
params + dataset id + qc_spec hash, with no model/prompt/seed involved), and reproducibility
buys four safety properties: bounded blast radius, model never on the critical path,
reviewable behaviour change, answerable incidents. Honest limit stated: determinism does not
make recipes *correct*, only reviewable, testable and attributable.

**§8.3 — how Skills are used.** Boundary rule: *Skills tune how the AI investigates and
words things; they never change which analysis runs and never change a QC threshold.*
Skills earn their place in failure triage, in the verification discipline itself
(`loop_validation`), as institutional-guardrail substrate, as the operator tool surface,
and for tuning without redeployment. Anti-pattern named explicitly: putting
"for RNA-seq use STAR" inside a Skill.

**§9.1 — Slack / Teams as the operator's secretary.** Answers a different question from the
other channels: not "can a human act?" but "will a human notice in time?". Two tiers, and
the boundary coincides with the governance boundary:
Tier A proactive digests/alerts = plain code, no LLM, safe to run unattended;
Tier B conversational = agent + Skills, **attended by construction** because a chat message
is a human-initiated invocation. Constraints recorded: Slack/Teams are external cloud (same
classification question, but about transport — Teams under the institutional tenancy is the
safer default, Slack needs a policy check); the bot inherits the allow-list (identifiers,
states, deadlines — never sample names or result content); chat identity must map to an LDAP
login before it can act (phase 1: read/veto/hold from chat, override/release from CLI);
alert fatigue is the failure mode. Build order: post-only webhook digest first (~1 day).

---

## 6. Open items

**Blocking the design (assigned)**

* **Falko** — what can we read in B-Fabric to learn that new data is in gStore? Field,
  values, latency. Also: can a comment be staff-only, on which entity? Service account?
* **Simon** — better order metadata (already asked). Which fields can become mandatory?
* **Customer-facing text owner** — wording and placement of the local-AI-model notice.
* **Operations** — business-hours confirmation, pilot scope, compute cap and low-priority
  QoS, what "forward the result" means concretely.
* **Chat platform** — Teams or Slack? Is either approved for FGCZ `internal` content? Who
  maps chat identities to LDAP?

**Answered on 2026-08-06**

* *Commit the untracked files?* — yes, docs only. `97221ea` on local `main`; not pushed.
* *Update the two overview HTMLs with the three new topics?* — yes. Done, 11 → 14 figures.

**Questions the user has not answered yet**

1. Run `multi_llm_review` on the deck (the presentation format's Step 5 gate), or do a
   slide-by-slide walkthrough instead?
2. Third catchphrase placement (format wants three; currently cover + S9 only — S6 or S8 is
   free).
3. Confirm "sample count / layout" belongs on the L0 allow-list (the reviewer's list ended
   with "...").
4. Should LLM-suggested resource parameters (cores/ram) be offered as a *non-binding
   suggestion* in the proposal? Offered as a possible v0.4 addition, not yet decided.
5. The overviews still say **v0.3 / 2026-07-31** in the header and footer, matching the md.
   Bump all four artifacts to v0.4, or leave the version as it is?

**To verify before citing to the team**

* The **M&M module in ezRun** — the user says it does its own LLM calls. I could not find it
  or any LLM reference in the 2026-07-17 ezRun checkout (`grep` for openai/gemini/llm/prompt
  found nothing in `R/` or `inst/`). Check the branch/version before using it as evidence in
  a message. The "one shared LLM service, because R + Ruby + Python cannot share a library"
  argument does not depend on it, but the example does.

---

## 7. Gotchas worth not rediscovering

**Deck → pptx**

* No headless browser on the FGCZ nodes (no chromium/chrome; only `pandoc`), so
  HTML→PDF→image→pptx is impossible. `deck_to_pptx.py` parses the deck's semantic markup and
  rebuilds slides from **native PowerPoint shapes** — editable, not screenshots.
* The deck is 1280×720 = **exactly 96 px/inch**, and a 16:9 pptx is 13.333×7.5 in, so HTML
  px map 1:1 (`Inches(px/96)`) and CSS px fonts → pt as `×0.75`.
* **python-pptx only exposes the latin typeface.** Japanese needs `<a:ea typeface="...">`
  injected into `rPr` by hand (`_set_fonts()`), or PowerPoint substitutes an arbitrary CJK
  font and breaks the computed metrics.
* **Diagrams in the deck are CSS primitives, not inline SVG** — that is what makes them
  convertible. Keep new slides inside the supported vocabulary (documented in the script's
  docstring): `two-col/col-card`, `three-col`, `four-col`, `stackrows/srow`, `flowrow/fbox`,
  `stat-row/stat-card`, `bullet-list`, `highlight-box[.orange|.pain|.proof]`, `key-point`,
  `table.spec`, `slide-footer`.
* The converter warns `content scaled to N%` when a slide is over-full. Two slides hit this
  and were fixed by splitting (Safety/Skills) and trimming. **Treat any warning as a slide
  to split, not to shrink.**
* `python-pptx` is **not** in `gi_py3.12.8`. Only found in other people's envs; used
  read-only:
  ```bash
  /misc/ngseq12/miniforge3/envs/ps_jlruiz_open-webui/bin/python \
    docs/presentations/deck_to_pptx.py \
    docs/presentations/omakase_auto_analysis_{en,ja}.html
  ```
  For durable use, install python-pptx into `gi_py3.12.8`.

**Illustrated overview HTMLs**

* SVG `<style>` blocks are **document-wide**, not scoped. A bare `.t` rule inside one SVG
  leaked into the `.callout .t` HTML titles; fixed by writing the full `font` shorthand on
  the more specific selector.
* `<b>` does **not** render inside an SVG `<text>`. Use `<tspan font-weight="700">`.
* Arrow markers live in one 0×0 `<svg>` at the top of `<body>` (not `display:none`, which
  can break marker resolution), so every later `<svg>` can reference `url(#ah)`.

**Editing at scale**

* Bulk edits were done with small Python scripts that assert each `old_string` exists and
  `sys.exit(1)` on a miss — worth repeating. Watch for double spaces in the SVG source
  (`class="t"  x="78"`), which broke one replacement.

**Writing style the user asked for repeatedly**

* Short sentences. Diagrams and tables over prose.
* When editing their draft text: **do not replace it wholesale** — keep their structure and
  length, change only what is wrong.
* No reference symbols the reader cannot resolve (no bare "Q5/Q6" in a message).
* Conversation in Japanese; all documentation in English.

---

## 8. Suggested next actions

1. Decide item 6.1 — `multi_llm_review` on the deck, or a slide-by-slide walkthrough.
2. The new overview figures were verified mechanically only (every `<svg>` parses, no banned
   wording, no estimated text overflow). **No browser rendering check was possible** — there
   is no headless browser on these nodes. Open both files in a real browser before showing
   them to anyone.
3. If a message to the team is next: the last approved draft kept the user's four-paragraph
   structure, ended with the AI-assistance note, and framed components as swappable rather
   than as a preference.
4. First real work item when the design is accepted (§17): the **metadata-readiness audit** —
   read-only over recent B-Fabric orders, reporting per service type how often Service Type /
   Sequencing Application / Species / Instrument / Library Protocol are usable, and how often
   the value is "Custom/Other" or empty. It doubles as the evidence for the request already
   made to Simon.
