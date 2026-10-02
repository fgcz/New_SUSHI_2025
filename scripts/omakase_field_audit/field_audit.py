#!/usr/bin/env python3
"""Which B-Fabric order (and sample) fields could help OMAKASE choose a recipe?

Today's `match` reads four order fields (service type, sequencing application, instrument,
library protocol) plus the sample count. The order endpoint returns about 50. This script
surveys all of them over the sequencing orders of the last N months, so the choice of what
else to read rests on fill rates rather than guesses.

Two passes, because order records are FGCZ `internal` and their values must not be printed
by default:

    inventory   per field: type, fill rate, distinct values, median length, and the fill
                rate inside the "gap" (orders whose service type + sequencing application
                cannot pick a recipe). NO values are printed.
    values F..  the value distribution of the named fields, printed only for values that
                occur in at least --min-count orders (default 5). Use it only on fields the
                inventory shows to be form drop-down lists, never on free text.
    samples     the same inventory for the samples of a sample of orders (no values).

Read-only by construction: the only B-Fabric call is `read`. No LLM. Nothing is cached to
disk.

    python -m omakase_field_audit.field_audit inventory
    python -m omakase_field_audit.field_audit values servicetype instrument
    python -m omakase_field_audit.field_audit samples --orders 60
"""
from __future__ import annotations

import argparse
import random
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta

from bfabric import Bfabric

TECHNOLOGY_SEQUENCING = "Genomics"
VAGUE_MARKERS = {"custom", "other", "misc", "unknown", "n/a", "na", "tbd", "-"}

# Never printed by `values`, whatever the inventory says: they name or describe people,
# projects or samples, or carry free text a customer typed.
NEVER_PRINT = {
    "name", "description", "comment", "comments", "remark", "remarks", "title", "label",
    "user", "users", "employee", "customer", "email", "login", "address", "phone",
    "createdby", "modifiedby", "statusmodifiedby", "project", "container", "sample",
    "samples", "abstract", "goal", "summary", "note", "notes", "instruction", "instructions",
}


def is_empty(v) -> bool:
    return v is None or v == "" or v == [] or v == {} or (isinstance(v, str) and not v.strip())


def kind_of(v) -> str:
    if isinstance(v, bool):
        return "bool"
    if isinstance(v, (int, float)):
        return "number"
    if isinstance(v, dict):
        return "ref:" + str(v.get("classname", "?")) if "id" in v else "dict"
    if isinstance(v, list):
        inner = {kind_of(x) for x in v[:5]} or {"?"}
        return "list[" + ",".join(sorted(inner)) + "]"
    return "str"


def scalar_key(v):
    """A hashable form used only for counting distinct values (never printed here)."""
    if isinstance(v, dict):
        return ("id", v.get("id"))
    if isinstance(v, list):
        return tuple(sorted(str(scalar_key(x)) for x in v))
    return str(v).strip()


def vague(v) -> bool:
    if is_empty(v):
        return True
    if isinstance(v, (dict, list, int, float)):
        return False
    text = str(v).strip().lower()
    words = {w.strip("()[]/,.") for w in text.replace("-", " ").split()}
    return bool(words & VAGUE_MARKERS) or text in VAGUE_MARKERS


def connect(env):
    client = Bfabric.from_config(config_env=env)
    print(f"instance: {client.config.base_url}", file=sys.stderr)
    return client


def fetch_orders(client, months):
    since = (datetime.now() - timedelta(days=int(months * 30.44))).strftime("%Y-%m-%d 00:00:00")
    print(f"reading orders created after {since} ...", file=sys.stderr)
    orders = list(client.read("order", {"createdafter": since}, max_results=None))
    seq = [o for o in orders if any(TECHNOLOGY_SEQUENCING in str(t)
                                     for t in (o.get("technology") or []))]
    print(f"  {len(orders)} orders, {len(seq)} sequencing", file=sys.stderr)
    return seq, since


def service_type_names(client, orders):
    ids = {int(o["servicetype"]["id"]) for o in orders
           if isinstance(o.get("servicetype"), dict) and o["servicetype"].get("id")}
    names = {}
    if ids:
        for row in client.read("servicetype", {"id": sorted(ids)}, max_results=None):
            names[int(row["id"])] = row.get("name") or f"id={row['id']}"
    return names


def st_label(o, names):
    st = o.get("servicetype")
    if isinstance(st, dict) and st.get("id"):
        return names.get(int(st["id"]), f"id={st['id']}")
    return "(none)"


def in_gap(o) -> bool:
    """Service type + sequencing application cannot pick a recipe on their own."""
    return vague(o.get("sequencingapplication")) or is_empty(o.get("servicetype"))


def inventory(records, gap_flags=None, header="order"):
    n = len(records)
    fields = sorted({k for r in records for k in r})
    gap_n = sum(gap_flags) if gap_flags else 0
    rows = []
    for f in fields:
        vals = [r.get(f) for r in records]
        filled = [v for v in vals if not is_empty(v)]
        kinds = Counter(kind_of(v) for v in filled)
        distinct = len({scalar_key(v) for v in filled})
        strs = [str(v) for v in filled if isinstance(v, str)]
        med_len = int(statistics.median(len(s) for s in strs)) if strs else 0
        gap_fill = (sum(1 for v, g in zip(vals, gap_flags) if g and not is_empty(v))
                    if gap_flags else 0)
        rows.append((f, kinds.most_common(1)[0][0] if kinds else "-", len(filled), distinct,
                     med_len, gap_fill))
    print(f"\n{header} fields: {len(fields)}   records: {n}"
          + (f"   gap records: {gap_n}" if gap_flags else ""))
    print(f"{'field':28} {'type':24} {'filled':>12} {'distinct':>8} {'medlen':>6}"
          + (f" {'filled in gap':>14}" if gap_flags else ""))
    for f, k, nf, d, ml, gf in sorted(rows, key=lambda r: -r[2]):
        line = f"{f:28} {k[:24]:24} {nf:5} {100*nf/n:5.1f}% {d:8} {ml:6}"
        if gap_flags:
            line += f" {gf:5} {100*gf/gap_n if gap_n else 0:6.1f}%"
        print(line)


def ref_names(client, classname, ids):
    """Resolve referenced entities to their `name` (drop-down entries, not people)."""
    out = {}
    try:
        for row in client.read(classname, {"id": sorted(ids)}, max_results=None):
            out[int(row["id"])] = row.get("name") or f"id={row['id']}"
    except Exception as exc:  # noqa: BLE001
        print(f"  ! cannot resolve {classname}: {exc}", file=sys.stderr)
    return out


def values(client, orders, names, fields, min_count):
    for f in fields:
        if f.lower() in NEVER_PRINT:
            print(f"\n{f}: refused (on the never-print list)")
            continue
        filled = [o.get(f) for o in orders if not is_empty(o.get(f))]
        flat = []
        for v in filled:
            flat.extend(v if isinstance(v, list) else [v])
        refs = [x for x in flat if isinstance(x, dict) and "id" in x]
        if refs:
            cls = refs[0].get("classname") or f
            resolved = ref_names(client, cls, {int(x["id"]) for x in refs})
            labels = [resolved.get(int(x["id"]), f"id={x['id']}") for x in refs]
        else:
            labels = [str(x).strip() for x in flat]
        c = Counter(labels)
        shown = [(v, k) for v, k in c.most_common() if k >= min_count]
        hidden = sum(k for v, k in c.items() if k < min_count)
        print(f"\n{f}: {len(filled)} orders filled, {len(c)} distinct values"
              f" ({len(c) - len(shown)} values under {min_count} orders not shown,"
              f" {hidden} occurrences)")
        for v, k in shown:
            print(f"  {k:5}  {v}")


def crosstab(client, orders, names, field, min_count):
    """Within each service type: how the field's values split, gap orders only."""
    if field.lower() in NEVER_PRINT:
        print(f"{field}: refused (on the never-print list)")
        return
    vals = [o.get(field) for o in orders]
    refs = {int(x["id"]): x.get("classname") or field for v in vals
            for x in (v if isinstance(v, list) else [v]) if isinstance(x, dict) and "id" in x}
    resolved = {}
    if refs:
        resolved = ref_names(client, next(iter(refs.values())), set(refs))

    def label(v):
        if is_empty(v):
            return "(empty)"
        items = v if isinstance(v, list) else [v]
        return " + ".join(sorted(resolved.get(int(x["id"]), f"id={x['id']}")
                                 if isinstance(x, dict) else str(x).strip() for x in items))

    table = defaultdict(Counter)
    for o in orders:
        if in_gap(o):
            table[st_label(o, names)][label(o.get(field))] += 1
    print(f"\n{field} inside the gap, by service type (values under {min_count} pooled)")
    for st, c in sorted(table.items(), key=lambda kv: -sum(kv[1].values())):
        print(f"  {st}  ({sum(c.values())})")
        small = 0
        for v, k in c.most_common():
            if k >= min_count:
                print(f"    {k:5}  {v}")
            else:
                small += k
        if small:
            print(f"    {small:5}  (other values, each under {min_count})")


# Keyword families for free-text fields. Only the COUNT of orders with a hit is printed,
# never the text: whether free text carries the assay or the species at all decides
# whether an on-prem model is worth pointing at it.
KEYWORDS = {
    "assay: bulk RNA": [r"\brna[- ]?seq", r"\bmrna\b", r"\btotal rna\b", r"\btranscriptom",
                        r"\bpoly ?a\b", r"\bribo[- ]?(zero|depl)", r"\bquant[- ]?seq"],
    "assay: small RNA": [r"\bsmall ?rna\b", r"\bmirna\b", r"\bmicro ?rna\b"],
    "assay: DNA (WGS/WES)": [r"\bwgs\b", r"\bwhole[- ]genome\b", r"\bwes\b", r"\bexome\b",
                             r"\bresequenc"],
    "assay: epigenome": [r"\batac\b", r"\bchip[- ]?seq\b", r"\bcut ?& ?(run|tag)\b",
                         r"\bmethyl", r"\bbisulfite\b", r"\bhi-?c\b"],
    "assay: amplicon/16S/meta": [r"\bamplicon\b", r"\b16s\b", r"\bits\b", r"\bmetagenom"],
    "assay: single cell / spatial": [r"\b10x\b", r"\bsingle[- ]?(cell|nuc)", r"\bscrna",
                                     r"\bsnrna", r"\bvisium\b", r"\bxenium\b", r"\bflex\b",
                                     r"\bmultiome\b", r"\bparse\b", r"\brhapsody\b"],
    "assay: CRISPR": [r"\bcrispr\b", r"\bsgrna\b", r"\bguide ?rna\b"],
    "species: human": [r"\bhuman\b", r"\bhomo\b", r"\bsapiens\b", r"\bhg38\b", r"\bgrch38\b"],
    "species: mouse": [r"\bmouse\b", r"\bmice\b", r"\bmus\b", r"\bmusculus\b", r"\bmm10\b",
                       r"\bgrcm3[89]\b"],
    "species: other named": [r"\brat\b", r"\barabidopsis\b", r"\bzebrafish\b",
                             r"\bdrosophila\b", r"\byeast\b", r"\bcerevisiae\b",
                             r"\be\.? ?coli\b", r"\bbacteri", r"\bplant\b", r"\bpig\b",
                             r"\bdog\b", r"\bcanis\b", r"\bc\.? ?elegans\b", r"\bxenopus\b"],
    "library kit named": [r"\btruseq\b", r"\bnebnext\b", r"\bsmart[- ]?seq\b", r"\billumina "
                          r"stranded\b", r"\bnextera\b", r"\bkapa\b", r"\btakara\b"],
    "strandedness named": [r"\bstranded\b", r"\bunstranded\b", r"\bnon[- ]?stranded\b"],
    "read layout named": [r"\bpaired[- ]?end\b", r"\bsingle[- ]?(end|read)\b",
                          r"\b(pe|sr)\s?\d{2,3}\b", r"\b2 ?x ?\d{2,3}\b"],
}


def keywords(orders, fields):
    import re
    pats = {fam: [re.compile(p, re.I) for p in ps] for fam, ps in KEYWORDS.items()}
    gap = [in_gap(o) for o in orders]
    n, gap_n = len(orders), sum(gap)
    for f in fields:
        texts = [str(o.get(f) or "") for o in orders]
        filled = sum(1 for t in texts if t.strip())
        print(f"\n{f}: free text on {filled} of {n} orders. Orders with at least one hit"
              f" (all / inside the gap of {gap_n}):")
        any_assay_all = any_assay_gap = 0
        for fam, ps in pats.items():
            hits = [any(p.search(t) for p in ps) for t in texts]
            h_all = sum(hits)
            h_gap = sum(1 for h, g in zip(hits, gap) if h and g)
            print(f"  {fam:30} {h_all:5} {100*h_all/n:5.1f}%   {h_gap:5} {100*h_gap/gap_n:5.1f}%")
        for t, g in zip(texts, gap):
            a = any(p.search(t) for fam, ps in pats.items() if fam.startswith("assay")
                    for p in ps)
            any_assay_all += a
            any_assay_gap += a and g
        print(f"  {'ANY assay family':30} {any_assay_all:5} {100*any_assay_all/n:5.1f}%"
              f"   {any_assay_gap:5} {100*any_assay_gap/gap_n:5.1f}%")


ANALYSIS_TYPES = {
    "High Throughput Sequencing (NGS)", "Single Cell Sequencing", "Spatial Gene Expression",
    "Long Read Sequencing", "ONT Ready-Made Libraries Sequencing", "CRISPR Screen",
}
RML = "Ready-made Libraries Sequencing"
# Sample fields whose values come from a drop-down (distinct counts 6-23 in the inventory).
SAMPLE_VOCAB = ["species", "type", "sourcetype", "multiplexkit", "samplepreparationprotocol",
                "extractionprotocolstring"]


def read_chunked(client, endpoint, ids):
    out = []
    ids = sorted(ids)
    for i in range(0, len(ids), 100):
        out.extend(client.read(endpoint, {"id": ids[i:i + 100]}, max_results=None))
    return out


def samplefields(client, orders, names, n_per_group, seed, min_count):
    """Per ORDER: which sample-level drop-downs are filled, gap (RML) vs the analysis types."""
    random.seed(seed)
    groups = {
        "RML, inside the gap": [o for o in orders if st_label(o, names) == RML and in_gap(o)],
        "RML, outside the gap": [o for o in orders if st_label(o, names) == RML
                                 and not in_gap(o)],
        "analysis service types": [o for o in orders if st_label(o, names) in ANALYSIS_TYPES],
    }
    ann_cache = {}
    for g, pool in groups.items():
        pick = random.sample(pool, min(n_per_group, len(pool)))
        per_field = {f: Counter() for f in SAMPLE_VOCAB}   # value -> number of ORDERS
        filled = Counter()                                  # field -> orders with any value
        single_species = 0
        for o in pick:
            try:
                recs = list(client.read("sample", {"containerid": int(o["id"])},
                                        max_results=100))
            except Exception as exc:  # noqa: BLE001
                print(f"  ! sample read failed: {exc}", file=sys.stderr)
                continue
            for f in SAMPLE_VOCAB:
                vals = set()
                for r in recs:
                    v = r.get(f)
                    if is_empty(v):
                        continue
                    if isinstance(v, dict) and "id" in v:
                        ann_cache.setdefault(int(v["id"]), None)
                        vals.add(("ann", int(v["id"])))
                    else:
                        vals.add(str(v).strip())
                if vals:
                    filled[f] += 1
                    for v in vals:
                        per_field[f][v] += 1
                    if f == "species" and len(vals) == 1:
                        single_species += 1
        missing = [i for i, n in ann_cache.items() if n is None]
        if missing:
            for row in read_chunked(client, "annotation", missing):
                ann_cache[int(row["id"])] = row.get("name") or f"id={row['id']}"
        n = len(pick)
        print(f"\n== {g}: {n} orders sampled of {len(pool)}")
        print(f"   orders where at least one sample carries the field:")
        for f in SAMPLE_VOCAB:
            extra = (f"   (exactly one species: {single_species})" if f == "species" else "")
            print(f"     {f:28} {filled[f]:4} {100*filled[f]/n if n else 0:5.1f}%{extra}")
        for f in SAMPLE_VOCAB:
            c = per_field[f]
            if not c:
                continue
            shown = [(v, k) for v, k in c.most_common() if k >= min_count]
            print(f"   {f}: values on at least {min_count} orders"
                  f" ({len(c) - len(shown)} rarer values not shown)")
            for v, k in shown:
                label = ann_cache.get(v[1]) if isinstance(v, tuple) else v
                print(f"     {k:4}  {label}")


def byapp(orders, names, fields, min_count):
    """Per Sequencing Application (canonical form, so the 'Single-Cell - ' and 'Spatial - '
    prefixes and the 'Experssion' typo fold together): value counts of the given drop-down
    fields, values on at least min_count orders only."""
    sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))
    from omakase_core.match import canonical
    groups = defaultdict(list)
    for o in orders:
        groups[canonical(o.get("sequencingapplication") or "(none)")].append(o)
    for app, pool in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        if len(pool) < min_count:
            continue
        wordings = Counter(str(o.get("sequencingapplication") or "(none)") for o in pool)
        print(f"\n== {app}: {len(pool)} orders; wordings: "
              + "; ".join(f"{w!r} {k}" for w, k in wordings.most_common() if k >= min_count))
        for f in fields:
            if f.lower() in NEVER_PRINT:
                continue
            c = Counter()
            for o in pool:
                v = o.get(f)
                items = v if isinstance(v, list) else [v]
                for x in items:
                    if isinstance(x, dict):
                        x = names.get(int(x["id"]), f"id={x['id']}") if f == "servicetype" else None
                    c["(empty)" if x is None or str(x).strip() == "" else str(x).strip()] += 1
            shown = [(v, k) for v, k in c.most_common() if k >= min_count]
            print(f"   {f}: " + "; ".join(f"{v} {k}" for v, k in shown)
                  + (f"  [+{sum(c.values()) - sum(k for _, k in shown)} in rarer values]"
                     if sum(c.values()) > sum(k for _, k in shown) else ""))


def nameshape(orders, names, field, min_count):
    """The SHAPE of a free-text field (letters -> a, digits -> 9, runs collapsed), and how
    often it equals the service type's name. Says whether the field is typed by a person
    or generated, without printing any text."""
    import re
    shapes = Counter()
    same_as_st = 0
    for o in orders:
        t = str(o.get(field) or "")
        if t.strip().lower() == st_label(o, names).strip().lower():
            same_as_st += 1
        s = re.sub(r"[A-Za-z]+", "a", t)
        s = re.sub(r"[0-9]+", "9", s)
        shapes[s] += 1
    print(f"\n{field}: equals the service type name on {same_as_st} of {len(orders)} orders")
    for s, k in shapes.most_common(10):
        if k >= min_count:
            print(f"  {k:5}  shape {s!r}")


def projectkeywords(client, orders, names):
    """Keyword families in the PROJECT summary of each order (counts only, no text)."""
    import re
    ids = {int(o["project"]["id"]) for o in orders if isinstance(o.get("project"), dict)}
    summ = {int(r["id"]): str(r.get("summary") or "") for r in read_chunked(client, "project", ids)}
    pats = {fam: [re.compile(p, re.I) for p in ps] for fam, ps in KEYWORDS.items()}
    groups = {
        "RML, inside the gap": [o for o in orders if st_label(o, names) == RML and in_gap(o)],
        "analysis service types": [o for o in orders if st_label(o, names) in ANALYSIS_TYPES],
    }
    for g, pool in groups.items():
        texts = [summ.get(int(o["project"]["id"]), "") for o in pool]
        n = len(texts)
        print(f"\n== project summary, {g}: {n} orders, {sum(1 for t in texts if t.strip())} with text")
        for fam, ps in pats.items():
            h = sum(1 for t in texts if any(p.search(t) for p in ps))
            print(f"  {fam:30} {h:5} {100*h/n if n else 0:5.1f}%")
        a = sum(1 for t in texts if any(p.search(t) for fam, ps in pats.items()
                                         if fam.startswith("assay") for p in ps))
        sp = sum(1 for t in texts if any(p.search(t) for fam, ps in pats.items()
                                          if fam.startswith("species") for p in ps))
        print(f"  {'ANY assay family':30} {a:5} {100*a/n if n else 0:5.1f}%")
        print(f"  {'ANY species family':30} {sp:5} {100*sp/n if n else 0:5.1f}%")
        pids = {int(o["project"]["id"]) for o in pool}
        pa = sum(1 for i in pids if any(p.search(summ.get(i, "")) for fam, ps in pats.items()
                                        if fam.startswith("assay") for p in ps))
        top = Counter(int(o["project"]["id"]) for o in pool).most_common(5)
        print(f"  distinct projects {len(pids)}; projects with ANY assay hit {pa}"
              f" ({100*pa/len(pids) if pids else 0:.1f}%); orders in the 5 largest projects:"
              f" {[k for _, k in top]}")


def projects(client, orders, n_orders, seed):
    random.seed(seed)
    pick = random.sample(orders, min(n_orders, len(orders)))
    ids = sorted({int(o["project"]["id"]) for o in pick if isinstance(o.get("project"), dict)})
    recs = read_chunked(client, "project", ids)
    print(f"  {len(recs)} projects from {len(pick)} orders", file=sys.stderr)
    if recs:
        inventory(recs, header="project")


def samples(client, orders, n_orders, seed):
    random.seed(seed)
    pick = random.sample(orders, min(n_orders, len(orders)))
    recs = []
    for o in pick:
        try:
            recs.extend(client.read("sample", {"containerid": int(o["id"])}, max_results=None))
        except Exception as exc:  # noqa: BLE001
            print(f"  ! sample read failed: {exc}", file=sys.stderr)
    print(f"  {len(recs)} samples from {len(pick)} orders", file=sys.stderr)
    if recs:
        inventory(recs, header="sample")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("mode", choices=["inventory", "values", "crosstab", "keywords", "samples",
                                     "projects", "samplefields", "nameshape", "projectkeywords", "byapp"])
    ap.add_argument("fields", nargs="*")
    ap.add_argument("--env", default="PRODUCTION")
    ap.add_argument("--months", type=float, default=12)
    ap.add_argument("--min-count", type=int, default=5)
    ap.add_argument("--orders", type=int, default=60, help="orders sampled by `samples`")
    ap.add_argument("--seed", type=int, default=20261001)
    ap.add_argument("--where", action="append", default=[], metavar="FIELD=VALUE",
                    help="keep only orders whose string FIELD equals VALUE (repeatable)")
    args = ap.parse_args(argv)
    if args.min_count < 5:
        ap.error("--min-count below 5 would print near-unique values")

    client = connect(args.env)
    orders, since = fetch_orders(client, args.months)
    names = service_type_names(client, orders)
    print(f"sequencing orders created after {since}: {len(orders)}")
    for cond in args.where:
        field, _, want = cond.partition("=")
        orders = [o for o in orders if str(o.get(field) or "").strip() == want.strip()]
        print(f"  where {field} == {want!r}: {len(orders)} orders")
    if args.mode == "inventory":
        gap = [in_gap(o) for o in orders]
        inventory(orders, gap)
    elif args.mode == "values":
        values(client, orders, names, args.fields, args.min_count)
    elif args.mode == "crosstab":
        for f in args.fields:
            crosstab(client, orders, names, f, args.min_count)
    elif args.mode == "keywords":
        keywords(orders, args.fields)
    elif args.mode == "projects":
        projects(client, orders, args.orders, args.seed)
    elif args.mode == "byapp":
        byapp(orders, names, args.fields, args.min_count)
    elif args.mode == "projectkeywords":
        projectkeywords(client, orders, names)
    elif args.mode == "nameshape":
        for f in args.fields:
            nameshape(orders, names, f, args.min_count)
    elif args.mode == "samplefields":
        samplefields(client, orders, names, args.orders, args.seed, args.min_count)
    else:
        samples(client, orders, args.orders, args.seed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
