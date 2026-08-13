#!/usr/bin/env python3
"""
How much of the REAL production workload does the legacy-app allow-list cover?

Reads the two snapshots next to this file (see README.md for how they were taken) and
prints coverage plus a ranked list of the apps worth allow-listing next. Touches nothing:
no database, no network. Re-run it after editing ALLOW below to see what a change buys.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
USAGE = os.environ.get('USAGE_TSV', os.path.join(HERE, 'app_usage_082_20260813.tsv'))
APPS = os.environ.get('PROD_APPS', os.path.join(HERE, 'prod_master_apps_20260813.txt'))
# Read the live allow-list out of the Rails config so this cannot drift from the code.
CONFIG = os.environ.get('APP_CONFIG',
                        os.path.join(HERE, '..', '..', 'backend', 'config', 'application.rb'))


def allow_list():
    """The default LEGACY_APPS_ALLOWLIST, parsed from config/application.rb."""
    try:
        src = open(CONFIG).read()
    except OSError:
        sys.exit(f'cannot read {CONFIG} (set APP_CONFIG)')
    m = re.search(r"ENV\.fetch\('LEGACY_APPS_ALLOWLIST',\s*(.*?)\)\s*\n\s*\.split", src, re.S)
    if not m:
        sys.exit('could not find the LEGACY_APPS_ALLOWLIST default in ' + CONFIG)
    names = ''.join(re.findall(r"'([^']*)'", m.group(1))).split(',')
    # FastqcApp is a backend-NATIVE port (backend/lib/apps), not an allow-list entry, so it
    # never appears in LEGACY_APPS_ALLOWLIST -- but it is exposed and must count as covered.
    return [n.strip() for n in names if n.strip()] + ['Fastqc']


def main():
    allow_ci = {(a + 'App').lower() for a in allow_list()}
    prod_ci = {l.strip().lower() for l in open(APPS) if l.strip()}

    agg = {}
    with open(USAGE) as fh:
        r = csv.reader(fh, delimiter='\t')
        next(r)
        for a in r:
            # Group case-insensitively: the prod DB collation is case-insensitive, so a
            # historical rename (ScSeuratApp / SCSeuratApp) is ONE app, not two.
            e = agg.setdefault(a[0].lower(),
                               dict(name=a[0], total=0, last='', y2026=0, y2025=0))
            e['total'] += int(a[1])
            e['y2026'] += int(a[3])
            e['y2025'] += int(a[4])
            if a[2] > e['last']:
                e['last'] = a[2]
                e['name'] = a[0]  # keep the most recent spelling as the label

    rows = list(agg.values())
    for x in rows:
        x['covered'] = x['name'].lower() in allow_ci
        x['live'] = x['name'].lower() in prod_ci  # the *App.rb still exists in prod master
        x['recent'] = x['y2025'] + x['y2026']

    def pct(a, b):
        return f'{100 * a / b:.1f}%' if b else 'n/a'

    live = [x for x in rows if x['live']]
    cov = [x for x in rows if x['covered']]
    tot, rec, r26 = (sum(x[k] for x in rows) for k in ('total', 'recent', 'y2026'))
    ltot, lrec, l26 = (sum(x[k] for x in live) for k in ('total', 'recent', 'y2026'))
    ctot, crec, c26 = (sum(x[k] for x in cov) for k in ('total', 'recent', 'y2026'))

    print(f'allow-list ({len(allow_ci)} apps): {", ".join(sorted(allow_list()))}\n')
    print('=== SCOPE ===')
    print(f'distinct app class names ever seen in prod : {len(rows)}')
    print(f'  of which the *App.rb still exists        : {len(live)}   '
          f'(retired: {len(rows) - len(live)})')
    print(f'legacy *App.rb files in prod master        : {len(prod_ci)}\n')

    print('=== COVERAGE (datasets produced) ===')
    print(f"{'window':12s} {'all apps':>10s} {'live apps':>10s} {'covered':>9s} "
          f"{'% of all':>9s} {'% of live':>10s}")
    for label, a, l, c in (('all-time', tot, ltot, ctot), ('2025+2026', rec, lrec, crec),
                           ('2026 only', r26, l26, c26)):
        print(f'{label:12s} {a:10d} {l:10d} {c:9d} {pct(c, a):>9s} {pct(c, l):>10s}')

    print('\n=== TOP 20 NOT covered, still live, by 2025+2026 ===')
    nc = sorted([x for x in rows if not x['covered'] and x['live']], key=lambda x: -x['recent'])
    print(f"{'#':>2s} {'app':32s} {'25+26':>6s} {'2026':>5s} {'total':>6s}  "
          f"{'last used':10s}  cumulative")
    run = crec
    for i, x in enumerate(nc[:20], 1):
        run += x['recent']
        print(f"{i:2d} {x['name']:32s} {x['recent']:6d} {x['y2026']:5d} {x['total']:6d}  "
              f"{x['last'][:10]:10s}  {pct(run, lrec)} of live")

    dead = [x for x in rows if not x['live'] and x['recent'] > 0]
    print(f"\n=== retired names (no *App.rb) with recent usage: {len(dead)} names, "
          f"{sum(x['recent'] for x in dead)} datasets = "
          f"{pct(sum(x['recent'] for x in dead), rec)} of 2025+2026 -- not portable ===")


if __name__ == '__main__':
    main()
