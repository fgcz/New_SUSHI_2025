# Mechanical gate for the illustrated HTML artifacts

There is no headless browser on the FGCZ nodes — no chromium, no chrome, only `pandoc`.
So "open it and look" cannot be done from a script or an agent session, and every
illustrated artifact under `docs/` has until now been verified by hand.

This checks the failure modes that have actually bitten this project, and nothing else.

```bash
python3 scripts/html_artifact_check/check.py docs/omakase-status-report-20260821-*.html
```

Exit code 1 if anything fails, so it can gate a commit.

## What it checks

| # | Check | Why it exists |
|---|---|---|
| 1 | every `<svg>` parses as XML | a truncated figure renders as nothing |
| 2 | no `<style>` inside an `<svg>` | SVG style blocks are **document-wide**, not scoped: a bare `.t` rule inside one figure once leaked into the page's callout titles |
| 3 | no `<b>` / `<strong>` / `<i>` inside SVG text | they do not render inside `<text>`; `<tspan font-weight="700">` is required |
| 4 | `<title>` belongs to the shape it labels | a stray `<title>` under `<svg>` silently overrides the figure's accessible name |
| 5 | estimated text width stays inside the viewBox | catches a label running off the canvas, honouring `text-anchor` |
| 6 | every `url(#id)` marker is defined | arrowheads live in one shared 0×0 `<svg>`; a typo leaves arrows headless |
| 7 | banned wording | naming conventions: write "SUSHI backend" / "REST API", and "SUSHI-MCP-server" |
| 8 | every `<figure>` has a `<figcaption>` | an uncaptioned figure is unreadable out of context |

Check 5 is an estimate, not typesetting: CJK glyphs are counted at 1.0 em, capitals and
digits at 0.62, the rest at 0.52. It is deliberately generous — it should complain only
when something is really about to fall off the edge.

HTML comments are blanked before scanning (line numbers preserved). That is required, not
cosmetic: these files contain comments that mention `<svg>` in prose, and a naive scan
matches from there to the next real `</svg>` and reports a parse error in a figure that is
perfectly fine.

## What it does NOT check

It is not a substitute for opening the file in a real browser once before showing it to
anyone. It knows nothing about layout, line wrapping, font substitution, or whether the
figure actually communicates anything.

## Known findings in the older artifacts

Run against `docs/omakase-auto-analysis-overview-{ja,en}.html` it reports the
`<style>`-inside-`<svg>` pattern on every figure, plus one `<figure>` without a
`<figcaption>` in the Japanese file. Those are pre-existing. The style leak is already
known and was mitigated by making the page's own selectors more specific rather than by
removing the SVG style blocks; the missing caption has not been looked at.
