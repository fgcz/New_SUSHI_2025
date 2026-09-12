# OMAKASE prototype deck — outline, timing and evidence inventory

**Deck:** `omakase_prototype_ja.html` / `omakase_prototype_en.html`
**Built by:** `build_omakase_prototype_deck.py` — edit the script, never the HTML
**Target:** ~10 minutes, 11 slides plus two appendices, one visual per slide
**Date of the talk:** 2026-09-16

One sentence the audience should leave with:

> A finished order can now become a proposed course of existing apps, a human
> approves it, and the system runs that course to the end — or stops with a reason.

Catchphrase, placed three times (cover, slide 3, slide 11 close):
**Rules decide, AI assists, humans release.**

---

## Names used in this deck

The internal code names are a Genomics-group matter and stay in the report. The
deck uses these instead, decided 2026-09-12.

| Internal code name | In this deck |
|---|---|
| SUSHI — the platform and its apps | **Omakase-Platform** / **Omakase-App** |
| SUSHI-MCP-server | **RecipeSkill-MCP-server** |
| Omics-Studio — the REST API | **Omakase-backend-API-server** |

`build_omakase_prototype_deck.py` fails the build if any of these old names — or
the earlier `Omakase-MCP-Server` — reappears in the generated HTML, so this cannot
drift back silently.

---

## The chain has six stages, not seven

The reference genome is **chosen, not derived**, and choosing it is part of
composing the recipe rather than a stage of its own. So there is no genome box in
the slide-3 chain. Recipe is **compose**, not **select** — the chef puts the course
together. What that does not mean, and slide 3 says so in one line: OMAKASE still
writes no apps, and the recipe catalog is still hand-written by a bioinformatician.

Slide 6 keeps the mechanism, reworded throughout from *derive* to *choose*: the
Species column picks one of five curated builds, and four cases refuse.

---

## Timing

| # | Slide | Min | The one thing to say |
|---|---|---|---|
| 1 | Cover | 0:25 | What OMAKASE stands for, and that the name is still provisional |
| 2 | Nothing happens today | 0:55 | An order reaches `processed` and no system reacts; analyses are started by hand, one app at a time |
| 3 | What OMAKASE does | 1:00 | Six stages, four of them running. It writes no apps — it composes a course from the ones that exist |
| 4 | Set subtraction | 0:45 | Ask for the whole set every tick and subtract what you handled. Being notified would be the lossy option |
| 5 | Order → data | 0:55 | 82 datasets down to one, and it declines rather than guessing. Order 35773 really was declined |
| 6 | Reference genome | 0:55 | Chosen from a curated list via the Species column. Four cases refuse — that is the feature |
| 7 | Human approval | 0:55 | History picks the right chain first only 17 % of the time. That is precisely why this is a proposal |
| 8 | Parallel | 1:15 | 6:31 against 12:13 serial, and the longest job is a leaf nobody waits for |
| 9 | Halting | 1:05 | The failed run left no submission row for step 2 at all. `afterany` would have started it |
| 10 | Two gaps | 1:10 | The recipe book fills one hand-written recipe at a time; nobody is told when a course is ready |
| 11 | Summary | 0:40 | The whole thing as a counter in a restaurant, with the real components underneath |

Two appendices are for questions, not for the ten minutes: **A** is the component
diagram with hermes-agent at the centre — the same shape as figure 1 of the report,
with only the names changed — and **B** is the five independent gates. Slide 11 and
Appendix A tell the same chain twice on purpose: once as a restaurant for the room,
once as components for whoever asks how it is wired.

---

## Evidence inventory

Every number on a slide, and where it was measured. Nothing here is projected.

| Slide | Claim | Source |
|---|---|---|
| 2 | 1 463 sequencing orders in 12 months | `scripts/omakase_metadata_audit/`, production, read-only, 2026-08-20 |
| 2, 7 | 304 of 426 real analyses are 2+ steps; top-1 is 71/421 | history audit, production, 2026-09-10 |
| 4 | 0.6–2.1 s per whole-set query; 30 orders ever at `processed` | bfabricPy against production, read-only, 2026-09-10 |
| 5 | 82 → 62 → 3 → 1; 7 detail calls; order 35773 declined | fgcz-h-083, 2026-09-11 |
| 6 | 5 species × 1 build; 42 752 reads over 6 795 `ENSMUSG` genes of 100 000 | `/srv/GT/reference-favorite`; FeatureCounts output, dataset 857, 2026-09-11 |
| 8 | 6:31 parallel, 12:13 serial, 3:25 critical path, 5:28 FastQC | SLURM 377297/377298/377300/377301/377306/377307, 2026-09-11 15:49–15:55 |
| 9 | Halt at 12:02:59, no submission row for step 2 | fgcz-h-083, candidate 2, 2026-09-11 |
| 9 | 87 transient end states in 30 118 jobs = 0.29 % | cluster accounting, jobs since 2026-09-01, read 2026-09-10 |
| 10 | The five recipe families: NGS, Single Cell, Spatial, Long Read, ONT | design §17 step 2 — the catalog a bioinformatician has to author |
| 10 | gStore copy latency 13 s – 1 229 s | every copy in p35611 on 2026-09-11 |
| 11, Appendix A | The chain, as a restaurant and as components | report `omakase-prototype-20260909-*.html`, figure 1 |
| Appendix B | The five independent gates, each verified by trying to get past it | report `omakase-prototype-20260909-*.html`, figure 4 |

---

## What the deck deliberately does not claim

- **Recipe composition does not work yet.** Slide 3 marks it with an orange cross
  and slide 10 shows the empty book. Today a recipe runs only when named on the
  command line.
- **Nobody is notified.** A proposal sits in SQLite; `omakase show --state PROPOSED`
  is the whole interface.
- **The course shown is one recipe, not a catalog.** `rnaseq_meeting_shape` with
  CountQC removed — CountQC fails inside its Quarto report on two samples, a
  pre-existing defect in the app that is recorded and deferred.
- **EdgeR's control-versus-target grouping is unbuilt.** It is the meeting's second
  judgement, and guessing it is the failure mode.
- **Nothing has run against production.** Every job in the deck ran on fgcz-h-083
  against its own database.

---

## Rebuilding and checking

```bash
python3 docs/presentations/build_omakase_prototype_deck.py
python3 scripts/html_artifact_check/check.py docs/presentations/omakase_prototype_*.html
```

The build itself verifies four things that cannot be seen without a browser, and
there is no browser on these nodes: every box and circle stays inside its own
canvas, the JA and EN figures are geometrically identical, the EN deck contains no
CJK, and none of the retired names has crept back in. `check.py` adds the
report-artifact rules — SVG parsing, text overflow, marker definitions.

Both must return `rc=0`. Neither replaces opening the deck in a real browser once.

## Presenting

`←` `→` or space to move, `R` to replay the current slide's animation, `F` for
fullscreen. `Ctrl+P` lays every slide out flat with the animations resolved, which
is how to produce a PDF fallback.

`deck_to_pptx.py` in this directory will **not** convert this deck faithfully — it
rebuilds slides from a text-block vocabulary (`.two-col`, `.stat-row`, …), and this
deck is one SVG per slide by design. Use the print path for a portable copy.
