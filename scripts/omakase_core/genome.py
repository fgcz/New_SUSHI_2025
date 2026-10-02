"""Which genome `reference_for(species)` gets: plain rules first, the on-prem model last.

    1   the input dataset's Species      reference.py: the catalog's per-assay policy for this
                                         recipe, else the curated favourite farm
    1b  the species on the order's B-Fabric samples (carried in the event by the watcher),
        only when the dataset carries NO usable Species - the same rules, other evidence
    2   hermes-agent on the FGCZ vLLM picks ONE curated species (genome_ai.py), only when 1
        and 1b cannot answer and only where allowed - and never final: the proposal gets
        checklist hold GENOME_ITEM, which a named person must confirm before the chain may
        start (constraints.py: an open before-start item refuses `approve`)

Decided with the user 2026-10-02. Steps 1 and 1b are deterministic and need no confirmation;
step 2 is the only place a model takes part, and it can only choose among the species the
farm already curates - which build a species gets is still the farm's (or the catalog's)
decision, never the model's.
"""
from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Callable

from . import constraints as K
from . import genome_ai, reference

GENOME_ITEM = 3000              # checklist index of the "model-suggested genome" hold


def ai_allowed(profile_name: str) -> bool:
    """On for `test`; off for `production` until someone decides otherwise.
    OMAKASE_GENOME_AI=on|off overrides both."""
    flag = os.environ.get("OMAKASE_GENOME_AI", "").strip().lower()
    if flag in ("on", "off"):
        return flag == "on"
    return profile_name == "test"


def _resolve(species_values: list[str], recipe_id: str | None, policy) -> tuple[str, str]:
    ds = {"samples": [{"Species": s} for s in species_values]}
    hit = reference.resolve_per_assay(ds, recipe_id, policy) if recipe_id and policy else None
    return hit or reference.resolve_for_dataset(ds)


def candidates() -> list[str]:
    """The curated species, as Latin names ("Mus musculus"): the model's whole vocabulary."""
    return sorted(k[:1].upper() + k[1:] for k in reference.builds())


def choose(dataset: dict, recipe_id: str | None, policy, *, sample_species=None,
           order: dict | None = None, allow_ai: bool = False,
           record: Callable[[dict], None] | None = None,
           ask: Callable[..., dict] = genome_ai.suggest
           ) -> tuple[str, str, dict | None]:
    """`(refBuild, how it was found, checklist item or None)`, or `reference.ReferenceError`."""
    # 1 - the dataset
    try:
        hit = reference.resolve_per_assay(dataset, recipe_id, policy) if recipe_id and policy else None
        build, how = hit or reference.resolve_for_dataset(dataset)
        return build, how, None
    except reference.ReferenceError as exc:
        refusal = exc
    on_dataset = reference.species_of(dataset)
    usable_samples = [s for s in (sample_species or [])
                      if reference.species_key(s) not in reference._ABSENT]

    # 1b - the order's B-Fabric samples, only when the dataset says nothing
    if not on_dataset and usable_samples:
        try:
            build, how = _resolve(usable_samples, recipe_id, policy)
            return build, ("from the order's B-Fabric sample species (the dataset carries "
                           f"none): {how}"), None
        except reference.ReferenceError as exc:
            refusal = exc

    # 2 - the on-prem model, constrained and never final
    if not allow_ai:
        raise refusal
    order = order or {}
    options = order.get("libraryprotocoloption")
    evidence = {
        "dataset_species": on_dataset,
        "bfabric_sample_species": usable_samples,
        "sequencing_application": order.get("sequencingapplication"),
        "library_protocol_options": options if isinstance(options, list) else
                                    ([options] if options else []),
        "recipe": recipe_id,
    }
    try:
        suggestion = ask(evidence, candidates(), reference.species_key)
    except genome_ai.AiUnavailable as exc:
        raise reference.ReferenceError(
            f"{refusal}; the on-prem model was asked too and gave no usable answer ({exc})"
        ) from None
    if record:
        record(suggestion)
    if suggestion["species"] == "UNKNOWN":
        raise reference.ReferenceError(
            f"{refusal}; the on-prem model ({suggestion['model']}) answers UNKNOWN: "
            f"{suggestion['reason']}")
    build, how = _resolve([suggestion["species"]], recipe_id, policy)
    item = {
        "idx": GENOME_ITEM, "kind": K.MANUAL, "severity": "hold", "at_step_seq": None,
        "assert": (f"the genome was SUGGESTED by the on-prem model, not derived: "
                   f"{suggestion['species']} -> {build}. Confirm it fits this dataset"),
        "reason": (f"{suggestion['model']} via hermes session {suggestion['session_id']} "
                   f"({suggestion['prompt_version']}); evidence {json.dumps(evidence)}"),
        "check": None, "status": K.PENDING,
        "detail": f"model says: {suggestion['reason']}",
    }
    return build, f"SUGGESTED by {suggestion['model']}: {how}", item


def recorder(directory: Path, order_id, dataset_id) -> Callable[[dict], None]:
    """Write each suggestion (inputs, answer, model, session) to a 600 file under the profile."""
    def write(suggestion: dict) -> None:
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / f"order{order_id}_ds{dataset_id}_{time.strftime('%Y%m%dT%H%M%S')}.json"
        path.write_text(json.dumps(suggestion, indent=2, ensure_ascii=False), encoding="utf-8")
        os.chmod(path, 0o600)
    return write


def carry_over(old: list[dict], new: list[dict], final_steps: list[dict]) -> list[dict]:
    """Keep the model-suggested-genome hold through a revision that still uses that genome.

    `revise` re-assesses the recipe's rules and would silently drop this item, letting a
    model's suggestion through unconfirmed. An unconfirmed one therefore refuses the
    revision; a confirmed one is kept, confirmed, with who confirmed it in its detail.
    """
    item = next((i for i in old if i["idx"] == GENOME_ITEM), None)
    if item is None:
        return new
    build = item["assert"].split(" -> ", 1)[-1].split(". Confirm", 1)[0]
    if build not in json.dumps(final_steps):
        return new                               # a person typed another genome themselves
    if item["status"] != K.CONFIRMED:
        raise reference.ReferenceError(
            f"the revised chain keeps the genome the on-prem model suggested ({build}); "
            f"confirm checklist item {GENOME_ITEM} first")
    kept = dict(item)
    kept["detail"] = (f"{item.get('detail') or ''}; confirmed by {item.get('confirmed_by')} "
                      f"at {item.get('confirmed_at')}, before the revision").lstrip("; ")
    return new + [kept]
