#!/usr/bin/env python3
"""
Where does the missing Species live? Cross the SUSHI dataset against the B-Fabric order.

`species_audit.py` shows that ~39% of raw datasets carry `NA` / `n/a` / blank in the
Species column. This script answers the follow-up that decides whether asking for a new
B-Fabric order field would fix it: **which service types are those datasets from?**

If the blank ones concentrate in one service type, the metadata request becomes a
targeted one ("make Species mandatory for THIS service type") instead of a general plea.

Input is the per-dataset TSV `order_id<TAB>species` produced by the SQL in README.md,
plus a read-only B-Fabric lookup of those orders' service type. Output is a cross-tab of
counts only -- no order ids, project names or sample names are printed.

    /misc/ngseq12/miniforge3/envs/gi_py3.12.8/bin/python crosscheck_order_service_type.py \
        --pairs /tmp/omakase_order_species.tsv --tsv service_type_crosstab.tsv
"""
import argparse
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import species_audit as sa  # noqa: E402

CHUNK = 100


def read_pairs(path):
    pairs = []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip('\n')
            if not line or line.startswith('SET SESSION') or line.startswith('order_id\t'):
                continue
            f = line.split('\t')
            if len(f) < 2 or not f[0].strip().isdigit():
                continue
            pairs.append((int(f[0]), f[1]))
    return pairs


def order_service_types(client, order_ids):
    """order id -> service-type name, read-only, in chunks."""
    st_id, out = {}, {}
    ids = sorted(order_ids)
    for i in range(0, len(ids), CHUNK):
        chunk = ids[i:i + CHUNK]
        for row in client.read('order', {'id': chunk}, max_results=None):
            st = row.get('servicetype') or {}
            sid = int(st['id']) if isinstance(st, dict) and st.get('id') else None
            st_id[int(row['id'])] = sid
        print(f'  read {min(i + CHUNK, len(ids))}/{len(ids)} orders', file=sys.stderr)

    names = {}
    wanted = {s for s in st_id.values() if s}
    if wanted:
        for row in client.read('servicetype', {'id': sorted(wanted)}, max_results=None):
            names[int(row['id'])] = row.get('name') or f"id={row['id']}"
    for oid, sid in st_id.items():
        out[oid] = names.get(sid, '(service type unknown)') if sid else '(no service type)'
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--pairs', required=True, help='order_id<TAB>species, one per dataset')
    ap.add_argument('--env', default='PRODUCTION', help='B-Fabric config env (default: PRODUCTION)')
    ap.add_argument('--tsv', help='write the cross-tab here')
    args = ap.parse_args()

    from bfabric import Bfabric

    pairs = read_pairs(args.pairs)
    if not pairs:
        sys.exit(f'no usable rows in {args.pairs}')

    by_species, fav = sa.catalog_builds()
    verdict = {r['raw']: r['verdict'] for r in sa.classify(
        [{'raw': s, 'datasets': 1, 'mixed': 0} for s in {s for _, s in pairs}],
        by_species, fav)}

    print(f'{len(pairs)} datasets, {len({o for o, _ in pairs})} distinct orders; '
          f'reading service types from B-Fabric {args.env} ...', file=sys.stderr)
    client = Bfabric.from_config(config_env=args.env)
    st = order_service_types(client, {o for o, _ in pairs})

    # Collapse the five verdicts to the two that matter here.
    def bucket(v):
        return 'unusable' if v == sa.VAGUE_V else 'usable'

    tab = defaultdict(Counter)
    for oid, sp in pairs:
        tab[st.get(oid, '(order not readable)')][bucket(verdict[sp])] += 1

    rows = sorted(tab.items(), key=lambda kv: -sum(kv[1].values()))
    tot_u = sum(c['unusable'] for _, c in rows)
    tot_all = sum(sum(c.values()) for _, c in rows)

    w = max(len(k) for k, _ in rows)
    print(f'\n{"service type":<{w}} {"datasets":>9} {"Species unusable":>17} {"share":>7}')
    for name, c in rows:
        n = sum(c.values())
        print(f'{name:<{w}} {n:>9} {c["unusable"]:>17} {100.0 * c["unusable"] / n:>6.1f}%')
    print(f'{"TOTAL":<{w}} {tot_all:>9} {tot_u:>17} {100.0 * tot_u / tot_all:>6.1f}%')

    if tot_u:
        print(f'\nOf the {tot_u} datasets with no usable Species, the top service type '
              f'accounts for '
              f'{100.0 * max(c["unusable"] for _, c in rows) / tot_u:.1f}%.')

    if args.tsv:
        with open(args.tsv, 'w') as fh:
            fh.write('service_type\tdatasets\tspecies_unusable\n')
            for name, c in rows:
                fh.write(f'{name}\t{sum(c.values())}\t{c["unusable"]}\n')
        print(f'\nwrote {args.tsv}', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
