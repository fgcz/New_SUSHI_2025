#!/usr/bin/env python3
"""
Mechanical gate for the illustrated HTML artifacts in docs/.

There is no headless browser on the FGCZ nodes, so "open it and look" is not
available in CI or in an agent session. This checks the failure modes that have
actually bitten this project before, and nothing else. It is not a substitute for
opening the file in a real browser once before showing it to anyone.

    python3 check.py docs/omakase-status-report-20260821-ja.html

Checks:

  1. every <svg> parses as XML
  2. no <style> inside an <svg> -- SVG style blocks are document-wide, not scoped,
     so a bare `.t` rule inside one figure leaks into the whole page
  3. no <b>/<strong>/<i> inside SVG text -- they do not render; <tspan> is required
  4. <title> is a child of the shape it describes, not a stray child of <svg>
     (which would silently override the figure's accessible name)
  5. estimated text width stays inside the viewBox, honouring text-anchor
  6. every marker referenced by url(#id) is defined somewhere in the document
  7. banned wording (naming conventions set for team-facing artifacts)
  8. figures are reachable: every <figure> has a <figcaption>

Exit code is 1 if anything fails, so it can gate a commit.
"""
import re
import sys
import xml.etree.ElementTree as ET

SVG_NS = 'http://www.w3.org/2000/svg'

# Naming rules for these artifacts. Left side is banned, right side says why.
BANNED = [
    (r'\bNew SUSHI backend\b', 'write "SUSHI backend" or "REST API" -- nothing on the '
                               'SUSHI side was invented for this project'),
    (r'\bKairosChain\b', 'write "SUSHI-MCP-server" in artifacts'),
    (r'\bsushi-chain\b', 'write "SUSHI-MCP-server" in artifacts'),
]

# Rough advance widths as a fraction of font-size. Deliberately generous: this
# check exists to catch a label running off the canvas, not to typeset.
W_CJK = 1.0
W_WIDE_LATIN = 0.62      # upper case and digits
W_LATIN = 0.52


def text_width(s, font_size):
    w = 0.0
    for ch in s:
        o = ord(ch)
        if o > 0x2E80:                     # CJK, kana, full-width punctuation
            w += W_CJK
        elif ch.isupper() or ch.isdigit():
            w += W_WIDE_LATIN
        else:
            w += W_LATIN
    return w * font_size


def strip_comments(src):
    """Blank out HTML comments, keeping line numbers.

    Required, not cosmetic: these files carry comments that mention `<svg>` in
    prose ("every later <svg> can reference url(#ah)"), and a naive scan matches
    from there to the next real `</svg>`, reporting a parse error in a figure that
    is perfectly fine.
    """
    return re.sub(r'<!--.*?-->',
                  lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)


def svg_blocks(src):
    """Every <svg>...</svg> with its 1-based start line."""
    out = []
    for m in re.finditer(r'<svg\b.*?</svg>', src, re.S):
        out.append((src.count('\n', 0, m.start()) + 1, m.group(0)))
    return out


def check_svg(block, line, problems):
    where = f'svg at line {line}'
    try:
        root = ET.fromstring(block)
    except ET.ParseError as exc:
        problems.append(f'{where}: does not parse -- {exc}')
        return

    def tag(el):
        return el.tag.split('}')[-1]

    if root.findall(f'.//{{{SVG_NS}}}style') or root.findall('.//style'):
        problems.append(f'{where}: contains a <style> block; SVG styles are '
                        f'document-wide and will leak into the page')

    for bad in ('b', 'strong', 'i', 'em'):
        if root.findall(f'.//{{{SVG_NS}}}{bad}') or root.findall(f'.//{bad}'):
            problems.append(f'{where}: <{bad}> does not render inside SVG text; '
                            f'use <tspan font-weight="700">')

    for child in root:
        if tag(child) == 'title' and list(root).index(child) != 0:
            problems.append(f'{where}: a <title> is a direct child of <svg> but not '
                            f'first ("{(child.text or "")[:40]}"); it belongs inside '
                            f'the shape it labels, or it overrides the accessible name')

    # A defs-only sprite (the arrow markers live in one 0x0 svg at the top of the
    # body, deliberately not display:none, which can break marker resolution) has
    # no canvas, so the geometry checks below do not apply to it.
    if root.get('width') == '0' and root.get('height') == '0':
        if list(root) and all(tag(c) == 'defs' for c in root):
            return
        problems.append(f'{where}: 0x0 but holds more than <defs>')
        return

    vb = root.get('viewBox')
    if not vb:
        problems.append(f'{where}: no viewBox, so it cannot scale')
        return
    try:
        _, _, vw, vh = [float(v) for v in vb.replace(',', ' ').split()]
    except ValueError:
        problems.append(f'{where}: unreadable viewBox {vb!r}')
        return

    for el in root.iter():
        if tag(el) != 'text':
            continue
        s = ''.join(el.itertext())
        if not s.strip():
            problems.append(f'{where}: an empty <text> element at x={el.get("x")} '
                            f'y={el.get("y")} -- delete it')
            continue
        try:
            x = float(el.get('x', 0))
            fs = float(el.get('font-size', 12))
        except ValueError:
            continue
        w = text_width(s, fs)
        anchor = el.get('text-anchor', 'start')
        left = x - w / 2 if anchor == 'middle' else (x - w if anchor == 'end' else x)
        right = left + w
        if right > vw + 1 or left < -1:
            problems.append(f'{where}: text may overflow the canvas '
                            f'(x={x:g}, anchor={anchor}, est. width {w:.0f}px, '
                            f'canvas {vw:g}px): "{s[:44]}"')
        try:
            y = float(el.get('y', 0))
            if y > vh + 1 or y < 0:
                problems.append(f'{where}: text baseline y={y:g} is outside the '
                                f'canvas height {vh:g}: "{s[:40]}"')
        except ValueError:
            pass


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    bad_total = 0
    for path in argv[1:]:
        src = strip_comments(open(path, encoding='utf-8').read())
        problems = []

        blocks = svg_blocks(src)
        if not blocks:
            problems.append('no <svg> found -- is this the right file?')
        for line, block in blocks:
            check_svg(block, line, problems)

        defined = set(re.findall(r'<marker\b[^>]*\bid="([^"]+)"', src))
        for ref in set(re.findall(r'url\(#([^)]+)\)', src)):
            if ref not in defined:
                problems.append(f'marker url(#{ref}) is referenced but never defined')

        # Skip the file's own <style> block: it legitimately names CSS classes.
        prose = re.sub(r'<style\b.*?</style>', '', src, flags=re.S)
        for pattern, why in BANNED:
            for m in re.finditer(pattern, prose):
                ln = prose.count('\n', 0, m.start()) + 1
                problems.append(f'line {ln}: banned wording "{m.group(0)}" -- {why}')

        figs = len(re.findall(r'<figure\b', src))
        caps = len(re.findall(r'<figcaption\b', src))
        if figs != caps:
            problems.append(f'{figs} <figure> but {caps} <figcaption>')

        print(f'{path}: {len(blocks)} svg, {figs} figures, '
              f'{len(problems)} problem(s)')
        for p in problems:
            print(f'  ! {p}')
        bad_total += len(problems)

    return 1 if bad_total else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
