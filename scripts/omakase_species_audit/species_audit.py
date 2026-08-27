#!/usr/bin/env python3
"""
OMAKASE decision D-a: can a recipe resolve a reference genome from what SUSHI knows?

Species does not exist in B-Fabric order metadata (see scripts/omakase_metadata_audit),
so the only place it exists is the SUSHI dataset. This script answers the follow-up
question that decides whether reading the dataset is enough:

    of the raw datasets that a finished order produces, how many carry a Species
    value that resolves to a reference build the recipe could actually name?

Two inputs, both read-only:

  * a snapshot TSV of `species -> dataset count` taken from the production SUSHI DB
    (the SQL is in README.md; no database access happens here)
  * the live reference catalog on disk, walked with the SAME globs that SUSHI's own
    `build_ref_selector` uses, so a "resolvable" verdict means the value really does
    appear in the refBuild dropdown

No LLM, no network, no writes. Species names are controlled vocabulary at the
institute level, not personal data, so they are printed verbatim; the snapshot
carries no project, order, sample or requester information.
"""
import argparse
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SNAPSHOT = os.path.join(HERE, 'species_snapshot_082_20260821.tsv')

# The two roots SUSHI offers builds from, and the curated one it lists FIRST.
# Kept in sync with backend/lib/global_variables.rb (GENOME_REF_DIRS / _FAVORITE).
GENOME_REF_DIRS = ['/srv/GT/reference', '/srv/GT/assembly']
GENOME_REF_DIRS_FAVORITE = ['/srv/GT/reference-favorite']

# Values that pass any "is it filled?" check but carry no decision content. The SUSHI
# equivalent of B-Fabric's `Custom / Other`. Compared lower-cased and stripped.
VAGUE = {'', 'na', 'n/a', 'n.a.', 'none', 'unknown', 'unidentified', 'other', '-', '?'}

# Claims about biology, not about code. Each line asserts that two strings name the
# same reference. NONE OF THESE ARE REVIEWED YET -- they are reported separately from
# the exact matches so the headline number never depends on them. A bioinformatician
# has to sign each one off before it may be used to resolve a real reference.
ALIASES_NEEDING_SIGNOFF = {
    'human': 'Homo_sapiens',
    'mouse': 'Mus_musculus',
    'canis_lupus_familiaris': 'Canis_familiaris',          # subspecies vs species dir
    'sus_linnaeus': 'Sus_scrofa',                           # "Sus Linnaeus (Pig)"
    'felis_silvestris_catus': 'Felis_catus',
    'salmonella_enterica_serovar_typhimurium': 'Salmonella_typhimurium',
    'oryza_sativa': 'Oryza_sativa_nipponbare',              # only cultivar in the catalog
    'human_immunodeficiency_virus': 'Human_immunodeficiency_virus-1',
    'a._halleri': 'Arabidopsis_halleri',                    # abbreviated genus
}


def normalise(raw):
    """Deterministic string cleanup only -- no biology.

    'Mus musculus (house mouse)' -> 'Mus_musculus'

    The trailing parenthetical is a common name that B-Fabric/NCBI appends; dropping it
    is a syntactic rule. Everything else is whitespace and separator handling. Case is
    NOT decided here: callers compare case-insensitively against the catalog.
    """
    s = raw.strip()
    s = re.sub(r'\s*\([^)]*\)\s*$', '', s).strip()   # drop one trailing parenthetical
    s = re.sub(r'\s+', '_', s)
    return s


def catalog_builds():
    """Every refBuild value SUSHI would offer, grouped by top-level species directory.

    Mirrors GlobalVariables#build_ref_selector: a bare <species>/<provider>/<build> is
    offered only when it has a Sequence/ directory and no Annotation/Version* or
    Annotation/Release* below it; those annotation directories are offered directly.
    """
    def rel(paths, roots):
        out = set()
        for p in paths:
            for r in roots:
                if p.startswith(r + '/'):
                    out.add(p[len(r) + 1:])
                    break
        return out

    def scan(roots):
        builds = rel([p for pat in roots for p in glob.glob(pat + '/*/*/*')
                      if os.path.isdir(p)], roots)
        versions = rel([p for pat in roots
                        for sub in ('Annotation/Version*', 'Annotation/Release*')
                        for p in glob.glob(pat + '/*/*/*/' + sub)
                        if os.path.isdir(p)], roots)
        sequences = rel([p for pat in roots for p in glob.glob(pat + '/*/*/*/Sequence')
                         if os.path.isdir(p)], roots)
        seq_parents = {os.path.dirname(s) for s in sequences}
        keep = {b for b in builds
                if b in seq_parents and not any(v.startswith(b + '/') for v in versions)}
        return keep | versions

    offered = scan(GENOME_REF_DIRS)
    favorite = scan(GENOME_REF_DIRS_FAVORITE)

    by_species, fav_by_species = {}, {}
    for b in sorted(offered):
        by_species.setdefault(b.split('/')[0], []).append(b)
    for b in sorted(favorite):
        fav_by_species.setdefault(b.split('/')[0], []).append(b)
    return by_species, fav_by_species


def read_snapshot(path):
    rows = []
    with open(path) as fh:
        header = fh.readline().rstrip('\n').split('\t')
        if header[:2] != ['species', 'datasets']:
            sys.exit(f'{path}: unexpected header {header!r}')
        for line in fh:
            if not line.strip('\n'):
                continue
            f = line.rstrip('\n').split('\t')
            rows.append({'raw': f[0],
                         'datasets': int(f[1]),
                         'mixed': int(f[2]) if len(f) > 2 else 0})
    return rows


# Verdicts, worst first when reporting.
RESOLVABLE = 'resolvable: curated build exists'
AMBIGUOUS = 'in catalog, but no curated build (a human picks)'
ALIAS = 'resolvable only via an UNREVIEWED alias'
NO_REFERENCE = 'named a species with no reference in the catalog'
VAGUE_V = 'no usable value (NA / n/a / blank)'


def classify(rows, by_species, fav_by_species):
    lookup = {k.lower(): k for k in by_species}
    fav_lookup = {k.lower(): k for k in fav_by_species}
    out = []
    for r in rows:
        raw, norm = r['raw'], normalise(r['raw'])
        key = norm.lower()
        rec = dict(r, normalised=norm, species_dir=None, refbuild=None, builds=0)

        if raw.strip().lower() in VAGUE or norm == '':
            rec['verdict'] = VAGUE_V
        elif key in fav_lookup:
            d = fav_lookup[key]
            rec.update(verdict=RESOLVABLE, species_dir=lookup.get(key, d),
                       refbuild=fav_by_species[d][0],
                       builds=len(by_species.get(lookup.get(key, d), [])))
        elif key in lookup:
            d = lookup[key]
            rec.update(verdict=AMBIGUOUS, species_dir=d, builds=len(by_species[d]))
        elif key in ALIASES_NEEDING_SIGNOFF:
            d = ALIASES_NEEDING_SIGNOFF[key]
            fav = fav_by_species.get(d)
            rec.update(verdict=ALIAS, species_dir=d,
                       refbuild=fav[0] if fav else None,
                       builds=len(by_species.get(d, [])))
        else:
            rec['verdict'] = NO_REFERENCE
        out.append(rec)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--snapshot', default=DEFAULT_SNAPSHOT)
    ap.add_argument('--json', metavar='FILE', help='also write the full classification')
    ap.add_argument('--resolve', metavar='SPECIES',
                    help='resolve one Species string and exit (the reference_for() probe)')
    args = ap.parse_args()

    missing = [d for d in GENOME_REF_DIRS + GENOME_REF_DIRS_FAVORITE if not os.path.isdir(d)]
    if missing:
        sys.exit('reference catalog not reachable from this host: ' + ', '.join(missing))

    by_species, fav_by_species = catalog_builds()

    if args.resolve:
        rec = classify([{'raw': args.resolve, 'datasets': 1, 'mixed': 0}],
                       by_species, fav_by_species)[0]
        print(f"input      : {rec['raw']!r}")
        print(f"normalised : {rec['normalised']}")
        print(f"verdict    : {rec['verdict']}")
        print(f"refBuild   : {rec['refbuild'] or '(none -- a human must pick)'}")
        print(f"candidates : {rec['builds']} build(s) in the catalog")
        return 0

    rows = classify(read_snapshot(args.snapshot), by_species, fav_by_species)
    total = sum(r['datasets'] for r in rows)
    mixed = sum(r['mixed'] for r in rows)

    # Not all of them are species: the catalog also holds control sequences, collections
    # and project-specific references (PhiX, Bacteria, p27821, ...).
    print(f'Reference catalog: {len(by_species)} top-level directories offer at least one '
          f'refBuild; {len(fav_by_species)} have a curated recommended build.')
    print(f'Snapshot: {args.snapshot}')
    print(f'{total} raw datasets from finished orders.\n')

    order = [RESOLVABLE, ALIAS, AMBIGUOUS, NO_REFERENCE, VAGUE_V]
    print(f'{"verdict":<48} {"datasets":>8} {"share":>7}  values')
    for v in order:
        sel = [r for r in rows if r['verdict'] == v]
        n = sum(r['datasets'] for r in sel)
        if not sel:
            continue
        print(f'{v:<48} {n:>8} {100.0 * n / total:>6.1f}% {len(sel):>6}')
    print(f'{"TOTAL":<48} {total:>8} {"100.0%":>7}')

    print(f'\nMixed-species datasets (more than one Species value in one dataset): '
          f'{mixed} = {100.0 * mixed / total:.1f}%. One refBuild cannot cover these.')

    for v in order:
        sel = sorted([r for r in rows if r['verdict'] == v],
                     key=lambda r: -r['datasets'])
        if not sel:
            continue
        print(f'\n--- {v} ---')
        for r in sel:
            tail = f"  -> {r['refbuild']}" if r['refbuild'] else (
                f"  -> {r['builds']} candidate build(s) under {r['species_dir']}"
                if r['species_dir'] else '')
            print(f"{r['datasets']:>5}  {r['raw']!r}{tail}")

    n_alias = sum(r['datasets'] for r in rows if r['verdict'] == ALIAS)
    if n_alias:
        print(f'\nWARNING: {n_alias} datasets are counted as ALIAS only. Those aliases are '
              f'claims about biology written by no reviewer yet; they must be signed off '
              f'before any recipe uses them.')

    if args.json:
        with open(args.json, 'w') as fh:
            json.dump({'snapshot': args.snapshot, 'total_datasets': total,
                       'mixed_species_datasets': mixed, 'rows': rows}, fh, indent=2)
        print(f'\nwrote {args.json}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
