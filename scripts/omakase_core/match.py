"""Does a recipe's `match` block accept an order? Deterministic, no model, fail closed.

A recipe (format v1) matches an order when EVERY constraint it writes is satisfied:

    service_type / sequencing_application / instrument / library_protocol /
    library_protocol_option / read_configuration / storage_model
        the order's value, canonicalised, is one of the recipe's values, canonicalised.
        `libraryprotocoloption` is a LIST on the order: it passes when ANY of its entries is
        in the recipe's list. An empty list does not constrain. An order without the field
        does not match.
    nuclei / samples_contain_transgenes   (true or false)
        the order states exactly that answer. An order that does not answer does not match:
        "unknown" is not "no", and a recipe that needs "no transgenes" must not run on
        samples nobody asked about.
    species                    the input DATASET's single Species is in the list
    species_in_reference_catalog: true
                               that Species resolves to a genome for THIS recipe
                               (per-assay policy, else the favourite farm); false = no demand
    samples {min, max}         the order's sample count is in range

and at least one of the string lists is non-empty: a block that constrains nothing matches
NO order (format v1 rule 8), so an unfinished `match` can never select every order.

Species is not an order field — the 2026-08-20 audit found none among 49 order and 13 sample
fields — so the two species rules need the input dataset. Without one they fail and say so
(`needs_dataset`), which is exactly what an order-level measurement should report.

Canonical form
--------------
Lower-case alphanumeric tokens (apostrophes kept, so 3' and 5' survive), with the two kinds
of duplicate the audit found in the live vocabulary folded:

    a category prefix     "Single-Cell - BD Rhapsody"       == "BD Rhapsody"
                          "Spatial - 10x Genomics - Visium" == "10x Genomics Visium"
    one known misspelling "Flex Gene Experssion"             == "Flex Gene Expression"

Then EXACT equality. Containment was tried by the audit and rejected: it also paired
"SARS-CoV-2 Whole Genome Sequencing" with "Whole Genome Sequencing", different services.
So a recipe that writes a different wording from B-Fabric's does not match — by design;
the measurement shows which wordings exist, and the recipe author decides.
"""
from __future__ import annotations

import re
from typing import Any

from . import reference

# recipe key -> order field (B-Fabric `order` endpoint, verified on production 2026-09-24;
# the last three and BOOL_FIELDS added 2026-10-01 from scripts/omakase_field_audit/)
ORDER_FIELDS = {
    "service_type": "servicetype",            # a {classname, id} dict: needs a name
    "sequencing_application": "sequencingapplication",
    "instrument": "instrument",
    "library_protocol": "libraryprotocol",
    "library_protocol_option": "libraryprotocoloption",   # a list on the order
    "read_configuration": "instrumentreadconfiguration",
    "storage_model": "storagemodel",
}
BOOL_FIELDS = {
    "nuclei": "nuclei",
    "samples_contain_transgenes": "samplescontaintransgenes",
}
STRING_LISTS = tuple(ORDER_FIELDS) + ("species",)
SPECIES_RULES = ("species", "species_in_reference_catalog")
TYPOS = {"experssion": "expression"}          # measured: 22 orders in 12 months
CATEGORY_PREFIXES = (("single", "cell"), ("spatial",))


def canonical(text: Any) -> str:
    s = str(text).lower().replace("’", "'").replace("‘", "'")
    tokens = [TYPOS.get(t, t) for t in re.sub(r"[^a-z0-9']+", " ", s).split()]
    for prefix in CATEGORY_PREFIXES:
        if tuple(tokens[:len(prefix)]) == prefix and len(tokens) > len(prefix):
            tokens = tokens[len(prefix):]
            break
    return " ".join(tokens)


def order_value(order: dict, key: str) -> str | None:
    """The order's value for a recipe key, or None when it is absent or unnamed."""
    values = order_values(order, key)
    return " + ".join(values) if values else None


def order_values(order: dict, key: str) -> list[str]:
    """Every value the order gives for a recipe key: one for most fields, several for a list
    field (`libraryprotocoloption`), none when absent or unnamed."""
    value = order.get(ORDER_FIELDS[key])
    items = value if isinstance(value, list) else [value]
    out = []
    for v in items:
        if isinstance(v, dict):
            # service type arrives as {classname, id}; only a resolved name can be matched
            v = v.get("name")
        if v is not None and str(v).strip() != "":
            out.append(str(v))
    return out


def order_bool(order: dict, key: str) -> bool | None:
    """True/False as the order states it; None when it does not say."""
    value = order.get(BOOL_FIELDS[key])
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.strip().lower() in ("true", "false"):
        return value.strip().lower() == "true"
    return None


def sample_count(order: dict) -> int | None:
    """Derived count first (81.1% present vs 70.9% declared, audit 2026-08-20)."""
    for field in ("countsamples", "numberofsamples"):
        n = order.get(field)
        if isinstance(n, int) and not isinstance(n, bool) and n > 0:
            return n
    return None


def evaluate(recipe: dict, order: dict, dataset: dict | None = None) -> dict[str, Any]:
    """Every rule of `recipe['match']` against one order: which passed, which did not, why."""
    m = recipe["match"]
    checks: list[tuple[str, bool, str]] = []
    needs_dataset = False
    if not any(m.get(k) for k in STRING_LISTS):
        return {"recipe": recipe["id"], "version": recipe["version"], "matches": False,
                "needs_dataset": False,
                "checks": [("match", False, "constrains nothing, so it matches no order "
                                            "(runs only when named)")]}
    for key in ORDER_FIELDS:
        wanted = m.get(key) or []
        if not wanted:
            continue
        have = order_values(order, key)
        if not have:
            checks.append((key, False, f"the order has no {ORDER_FIELDS[key]}"))
            continue
        allowed = {canonical(w) for w in wanted}
        ok = any(canonical(h) in allowed for h in have)
        shown = have[0] if len(have) == 1 else have
        checks.append((key, ok, f"{shown!r} " + ("is" if ok else "is not") + " in the list"))
    for key, field in BOOL_FIELDS.items():
        if key not in m:
            continue
        have_b = order_bool(order, key)
        if have_b is None:
            checks.append((key, False, f"the order does not say ({field} absent)"))
        else:
            checks.append((key, have_b is m[key],
                           f"the order says {have_b}, the recipe needs {m[key]}"))
    species, why_not = None, "Species is on the dataset, not the order"
    if dataset is not None and (m.get("species") or m.get("species_in_reference_catalog") is True):
        try:
            species = reference._one_species(reference.species_of(dataset))
        except reference.ReferenceError as exc:
            why_not = str(exc)
    for rule in SPECIES_RULES:
        demanded = (bool(m.get("species")) if rule == "species"
                    else m.get("species_in_reference_catalog") is True)
        if not demanded:
            continue
        if dataset is None:
            needs_dataset = True
            checks.append((rule, False, why_not))
        elif species is None:
            checks.append((rule, False, why_not))
        elif rule == "species":
            ok = reference.species_key(species) in {reference.species_key(x) for x in m["species"]}
            checks.append((rule, ok, f"{species!r} " + ("is" if ok else "is not") + " in the list"))
        else:
            checks.append((rule,) + _in_catalog(recipe, dataset))
    if m.get("samples"):
        lo, hi = m["samples"]["min"], m["samples"]["max"]
        n = sample_count(order)
        if n is None:
            checks.append(("samples", False, "the order states no sample count"))
        else:
            checks.append(("samples", lo <= n <= hi, f"{n} samples, recipe takes {lo}-{hi}"))
    return {"recipe": recipe["id"], "version": recipe["version"], "needs_dataset": needs_dataset,
            "matches": bool(checks) and all(ok for _, ok, _ in checks),
            "checks": checks}


def _in_catalog(recipe: dict, dataset: dict) -> tuple[bool, str]:
    from . import recipes  # late: recipes imports this module's caller chain
    policy = recipes.reference_policy()
    try:
        hit = reference.resolve_per_assay(dataset, recipe["id"], policy) if policy else None
        build, how = hit or reference.resolve_for_dataset(dataset)
        return True, how
    except reference.ReferenceError as exc:
        return False, str(exc)


def order_level_ok(result: dict) -> bool:
    """Everything the ORDER can answer passed (the species rules aside)."""
    order_checks = [ok for k, ok, _ in result["checks"] if k not in SPECIES_RULES]
    return bool(order_checks) and all(order_checks)


def describe(result: dict) -> str:
    """One line per recipe: why it did or did not match."""
    head = f"{result['recipe']}@{result['version']}"
    if result["matches"]:
        return f"{head}  MATCH"
    if result["needs_dataset"] and order_level_ok(result):
        return f"{head}  order-level pass; the species rules need the dataset"
    failed = [f"{k}: {why}" for k, ok, why in result["checks"] if not ok]
    return f"{head}  no — " + "; ".join(failed)
