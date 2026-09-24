"""Recipe loading — recipe format v1.

"v1" is the first frozen version of the recipe *file format* (the draft proposal to Paul
Gueguen is docs/omakase-recipe-format-v1/PROPOSAL.md, untracked until he agrees). It is
his MR !1 format plus optional keys only, so his catalog loads without edits:

    app / params                 the SUSHI app class and its parameters
    list order                   = dependency; `id` + `after: [id]` only where it is not
    {{ reference_for(species) }} the genome, derived per assay (catalog references.yaml)
    {{ same_as_previous }}       the same key's value on the one upstream step
    YAML list                    a multi-select, comma-joined for SUSHI
    retry_params                 overlay for the single automatic resubmission
    constraints: assert/check/at the rules checked before submission (evaluated in step 3)

Where recipes come from
-----------------------
Two directories, never merged by id (the same id in both is an error):

* `recipes/` next to this file — the engine's own FIXTURES, committed here. They exercise
  the machinery; none is a signed-off recipe, and every one matches no order.
* the CATALOG — `$OMAKASE_CATALOG_DIR`, default the local clone of Paul's MR at
  `paul-scripts/Internal_Dev/omakase` (gitignored). It is read, never copied into this
  repository: the repository is public on GitHub and the catalog is his work, shared when
  he agrees (open question Q7 of the proposal). Its `references.yaml` is the per-assay
  genome policy.

Everything this module returns uses the engine's internal step shape — `seq`, `app_name`,
`parameters`, `retry_parameters`, `depends_on_seq` — which the store, the runner and the
panel already speak, so v1 is a translation at the edge and nothing downstream changed.

Deliberate limits, each a refusal rather than a guess:
* `after` may name at most ONE step. SUSHI apps take one input dataset, and with two
  upstream steps it would be ambiguous whose output is the input.
* A template must be the whole value (`refBuild: "{{ reference_for(species) }}"`), never
  spliced into a longer string.
* `when` and `constraints` are parsed and validated here, and evaluated by ingest.
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

import yaml

from . import reference

FIXTURE_DIR = Path(__file__).parent / "recipes"
DEFAULT_CATALOG = Path("/srv/sushi/masa_test_new_sushi_20260527/paul-scripts/Internal_Dev/omakase")

# Internal sentinels the two templates compile to. They are expanded against the input
# dataset BEFORE the proposal is stored, so the approver sees the real genome path.
FROM_SPECIES = "FROM_SPECIES"
SAME_AS_PREVIOUS = "SAME_AS_PREVIOUS"
TEMPLATES = {"reference_for(species)": FROM_SPECIES, "same_as_previous": SAME_AS_PREVIOUS}

FILENAME_RE = re.compile(r"^(?P<id>[a-z0-9]+(?:_[a-z0-9]+)*)_v(?P<version>\d+)\.yaml$")
ID_RE = re.compile(r"^[a-z0-9]+(?:_[a-z0-9]+)*$")
APP_RE = re.compile(r"^[A-Za-z0-9_]+$")
TEMPLATE_RE = re.compile(r"\{\{\s*(?P<expr>.+?)\s*\}\}")
VERSION_RE = re.compile(r"^[0-9]+(\.[0-9]+)*$")

TOP_KEYS = {"schema_version", "id", "version", "author", "description", "match", "steps",
            "constraints", "qc_spec", "qc_spec_sha256", "budget", "autostart",
            "autostart_blocked_by", "notes"}
TOP_REQUIRED = ("id", "version", "author", "match", "steps", "autostart")
STEP_KEYS = {"id", "after", "app", "params", "retry_params", "when", "note"}
CONSTRAINT_KEYS = {"assert", "check", "at", "reason", "severity"}
MATCH_LISTS = ("service_type", "sequencing_application", "instrument", "library_protocol",
               "species")
MATCH_KEYS = set(MATCH_LISTS) | {"species_in_reference_catalog", "samples"}
OPERATORS = {"equals", "one_of", "contains", "matches", "version_at_least"}


class RecipeError(RuntimeError):
    pass


# ------------------------------------------------------------------------- where


def catalog_dir() -> Path | None:
    """The catalog root, or None. `OMAKASE_CATALOG_DIR=` (empty) switches it off."""
    raw = os.environ.get("OMAKASE_CATALOG_DIR")
    if raw == "":
        return None
    path = Path(raw) if raw else DEFAULT_CATALOG
    return path if (path / "recipes").is_dir() else None


def reference_policy() -> Path | None:
    root = catalog_dir()
    return root / "references.yaml" if root else None


def _sources() -> list[tuple[str, Path]]:
    out = [("fixture", FIXTURE_DIR)]
    root = catalog_dir()
    if root:
        out.append(("catalog", root / "recipes"))
    return out


def _index() -> tuple[dict[str, list[tuple[int, Path, str]]], list[str]]:
    """id -> [(version, path, source)], plus the problems found while listing."""
    found: dict[str, list[tuple[int, Path, str]]] = {}
    problems: list[str] = []
    for source, directory in _sources():
        for path in sorted(directory.glob("*.yaml")):
            m = FILENAME_RE.match(path.name)
            if not m:
                problems.append(f"{path}: filename must be <id>_v<N>.yaml")
                continue
            found.setdefault(m["id"], []).append((int(m["version"]), path, source))
    for rid, entries in found.items():
        if len({src for _, _, src in entries}) > 1:
            problems.append(f"recipe id {rid!r} exists in both the fixtures and the catalog")
    return found, problems


def available() -> list[str]:
    return sorted(_index()[0])


# ------------------------------------------------------------------------- load


def load(recipe_id: str, version: int | None = None) -> dict[str, Any]:
    """The highest version of `recipe_id` (or exactly `version`), validated and compiled."""
    index, problems = _index()
    clash = [p for p in problems if f"{recipe_id!r}" in p]
    if clash:
        raise RecipeError(clash[0])
    entries = index.get(recipe_id)
    if not entries:
        where = ", ".join(str(d) for _, d in _sources())
        raise RecipeError(f"no recipe {recipe_id!r} in {where}")
    entries = sorted(entries)
    if version is not None:
        entries = [e for e in entries if e[0] == version]
        if not entries:
            raise RecipeError(f"recipe {recipe_id!r} has no version {version}")
    ver, path, source = entries[-1]
    with path.open(encoding="utf-8") as fh:
        raw = yaml.safe_load(fh)
    errors = validate(raw, path)
    if errors:
        raise RecipeError(f"{path.name} is not a valid v1 recipe:\n  - " + "\n  - ".join(errors))
    return {
        "id": raw["id"],
        "version": int(raw["version"]),
        "author": raw["author"],
        "description": raw.get("description"),
        "match": raw["match"],
        "autostart": raw["autostart"],
        "constraints": raw.get("constraints") or [],
        "qc_spec": raw.get("qc_spec"),
        "budget": raw.get("budget"),
        "steps": compile_steps(raw["steps"]),
        "source": source,
        "path": str(path),
    }


# ------------------------------------------------------------------------- validate


def validate(raw: Any, path: Path) -> list[str]:
    """Every way `raw` departs from format v1. Empty means valid."""
    errs: list[str] = []
    if not isinstance(raw, dict):
        return ["top level is not a mapping"]
    for key in sorted(set(raw) - TOP_KEYS):
        errs.append(f"unknown top-level key {key!r}")
    for key in TOP_REQUIRED:
        if key not in raw:
            errs.append(f"missing required key {key!r}")
    if raw.get("schema_version", 1) != 1:
        errs.append(f"schema_version {raw.get('schema_version')!r}: this engine reads v1 only")
    m = FILENAME_RE.match(path.name)
    if m and (raw.get("id") != m["id"] or raw.get("version") != int(m["version"])):
        errs.append(f"id/version {raw.get('id')!r}/{raw.get('version')!r} do not match the "
                    f"filename {path.name}")
    if not isinstance(raw.get("version"), int) or isinstance(raw.get("version"), bool) \
            or raw.get("version", 0) < 1:
        errs.append("version must be an integer >= 1")
    if raw.get("autostart") is False and not raw.get("autostart_blocked_by"):
        errs.append("autostart: false needs autostart_blocked_by")
    errs += _validate_match(raw.get("match"))
    steps = raw.get("steps")
    if not isinstance(steps, list) or not steps:
        errs.append("steps must be a non-empty list")
        return errs
    errs += _validate_steps(steps)
    for i, con in enumerate(raw.get("constraints") or []):
        errs += [f"constraints[{i}]: {e}" for e in _validate_constraint(con, steps)]
    return errs


def _validate_match(match: Any) -> list[str]:
    if not isinstance(match, dict):
        return ["match must be a mapping"]
    errs = [f"match: unknown key {k!r}" for k in sorted(set(match) - MATCH_KEYS)]
    for k in MATCH_LISTS:
        if k in match and not (isinstance(match[k], list)
                               and all(isinstance(v, str) for v in match[k])):
            errs.append(f"match.{k} must be a list of strings (empty = do not constrain)")
    if "species_in_reference_catalog" in match and \
            not isinstance(match["species_in_reference_catalog"], bool):
        errs.append("match.species_in_reference_catalog must be true or false")
    samples = match.get("samples")
    if samples is not None and not (isinstance(samples, dict) and set(samples) == {"min", "max"}
                                    and all(isinstance(samples[k], int) and samples[k] >= 1
                                            for k in ("min", "max"))):
        errs.append("match.samples must be {min: N, max: M} with N, M >= 1")
    return errs


def _validate_steps(steps: list) -> list[str]:
    errs: list[str] = []
    ids: dict[str, int] = {}
    for i, step in enumerate(steps):
        where = f"steps[{i}]"
        if not isinstance(step, dict):
            errs.append(f"{where}: not a mapping")
            continue
        errs += [f"{where}: unknown key {k!r}" for k in sorted(set(step) - STEP_KEYS)]
        app = step.get("app")
        if not isinstance(app, str) or not APP_RE.match(app):
            errs.append(f"{where}: app must be a SUSHI app class name")
        if "id" in step:
            if not isinstance(step["id"], str) or not ID_RE.match(step["id"]):
                errs.append(f"{where}: id must be snake_case")
            elif step["id"] in ids:
                errs.append(f"{where}: duplicate step id {step['id']!r}")
            else:
                ids[step["id"]] = i
        if "after" in step:
            after = step["after"]
            if not isinstance(after, list) or not all(isinstance(a, str) for a in after):
                errs.append(f"{where}: after must be a list of step ids")
            elif len(after) > 1:
                errs.append(f"{where}: after names {len(after)} steps; this engine allows one, "
                            f"because a SUSHI app takes one input dataset and it would be "
                            f"ambiguous whose output that is")
            else:
                for name in after:
                    if name not in ids:
                        errs.append(f"{where}: after names {name!r}, which is not an EARLIER "
                                    f"step id")
        for key in ("params", "retry_params"):
            params = step.get(key)
            if params is None:
                continue
            if not isinstance(params, dict):
                errs.append(f"{where}.{key} must be a mapping")
                continue
            for pkey, value in params.items():
                errs += [f"{where}.{key}.{pkey}: {e}" for e in _validate_value(value)]
        if "when" in step and not isinstance(step["when"], str):
            errs.append(f"{where}: when must be a string")
    # same_as_previous needs exactly one upstream step
    for i, step in enumerate(steps):
        if not isinstance(step, dict):
            continue
        for key in ("params", "retry_params"):
            for pkey, value in (step.get(key) or {}).items():
                if _template(value) == SAME_AS_PREVIOUS and _upstream(steps, i) is None:
                    errs.append(f"steps[{i}].{key}.{pkey}: same_as_previous needs exactly one "
                                f"upstream step, and this step has none")
    return errs


def _validate_value(value: Any) -> list[str]:
    values = value if isinstance(value, list) else [value]
    errs = []
    for v in values:
        if isinstance(v, (dict, list)):
            errs.append("values must be scalars or a list of scalars")
            continue
        if v in (FROM_SPECIES, SAME_AS_PREVIOUS):
            errs.append(f"write the template, not the internal sentinel {v!r}")
        s = str(v)
        hits = list(TEMPLATE_RE.finditer(s))
        for h in hits:
            if h["expr"] not in TEMPLATES:
                errs.append(f"unknown template {{{{ {h['expr']} }}}}; allowed: "
                            + ", ".join(f"{{{{ {t} }}}}" for t in TEMPLATES))
        if hits and (isinstance(value, list) or not TEMPLATE_RE.fullmatch(s.strip())):
            errs.append("a template must be the whole value")
    return errs


def _validate_constraint(con: Any, steps: list) -> list[str]:
    if not isinstance(con, dict):
        return ["not a mapping"]
    errs = [f"unknown key {k!r}" for k in sorted(set(con) - CONSTRAINT_KEYS)]
    for key in ("assert", "reason"):
        if not isinstance(con.get(key), str) or not con.get(key):
            errs.append(f"{key} is required text")
    if con.get("severity", "refuse") not in ("refuse", "hold"):
        errs.append("severity must be refuse or hold")
    chk = con.get("check", "manual")
    if chk != "manual":
        errs += _validate_check(chk, steps)
    at = con.get("at", "before_submit")
    if at != "before_submit":
        if not (isinstance(at, dict) and set(at) == {"before_step"}):
            errs.append("at must be before_submit or {before_step: <step>}")
        else:
            errs += _step_ref_errors(at["before_step"], steps)
    return errs


def _validate_check(expr: Any, steps: list) -> list[str]:
    if not isinstance(expr, dict):
        return [f"check must be 'manual' or a check expression, not {expr!r}"]
    for combinator in ("all", "any"):
        if combinator in expr:
            if set(expr) != {combinator} or not isinstance(expr[combinator], list) \
                    or not expr[combinator]:
                return [f"{combinator} must be the only key and hold a non-empty list"]
            return [e for sub in expr[combinator] for e in _validate_check(sub, steps)]
    if "not" in expr:
        return (["not must be the only key"] if set(expr) != {"not"}
                else _validate_check(expr["not"], steps))
    if "if" in expr or "then" in expr:
        if set(expr) != {"if", "then"}:
            return ["if needs then, and nothing else"]
        return _validate_check(expr["if"], steps) + _validate_check(expr["then"], steps)
    ops = set(expr) - {"step", "param"}
    errs = []
    if not {"step", "param"} <= set(expr):
        errs.append("a test needs step and param")
    if len(ops) != 1 or not ops <= OPERATORS:
        errs.append(f"a test needs exactly one operator of {sorted(OPERATORS)}, got {sorted(ops)}")
        return errs
    op = next(iter(ops))
    val = expr[op]
    if op == "one_of" and not (isinstance(val, list) and val):
        errs.append("one_of needs a non-empty list")
    if op in ("contains", "matches") and not (isinstance(val, str) and val):
        errs.append(f"{op} needs a non-empty string")
    if op == "matches":
        try:
            re.compile(val)
        except (re.error, TypeError) as exc:
            errs.append(f"matches: not a regular expression ({exc})")
    if op == "version_at_least" and not (isinstance(val, str) and VERSION_RE.match(val)):
        errs.append("version_at_least needs a dotted version like '10.1.0'")
    if "step" in expr:
        errs += _step_ref_errors(expr["step"], steps)
    return errs


def step_index(ref: str, steps: list) -> list[int]:
    """Indices a step reference names: an id, else an app name with or without `App`."""
    hits = [i for i, s in enumerate(steps) if s.get("id") == ref]
    if hits:
        return hits
    base = ref[:-3] if ref.endswith("App") else ref
    return [i for i, s in enumerate(steps)
            if "id" not in s and str(s.get("app", s.get("app_name", ""))).removesuffix("App") == base]


def _step_ref_errors(ref: Any, steps: list) -> list[str]:
    if not isinstance(ref, str):
        return ["a step reference must be a string"]
    n = len(step_index(ref, steps))
    return [] if n == 1 else [f"step {ref!r} names {n} steps; it must name exactly one"]


# ------------------------------------------------------------------------- compile


def _template(value: Any) -> str | None:
    m = TEMPLATE_RE.fullmatch(str(value).strip()) if isinstance(value, str) else None
    return TEMPLATES.get(m["expr"]) if m else None


def _upstream(steps: list, i: int) -> int | None:
    """Index of step i's single upstream step, or None when it starts with the chain."""
    after = steps[i].get("after")
    if after is None:
        return i - 1 if i > 0 else None
    if not after:
        return None
    return next(j for j, s in enumerate(steps) if s.get("id") == after[0])


def _value(value: Any) -> Any:
    """A v1 parameter value as the engine submits it: templates to sentinels, lists joined."""
    if isinstance(value, list):
        return ",".join(str(v) for v in value)   # a multi-select; SUSHI wants one string
    return _template(value) or value


def compile_steps(steps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """v1 steps -> the engine's internal steps (seq / app_name / parameters / ...)."""
    out = []
    for i, step in enumerate(steps):
        params = {k: _value(v) for k, v in (step.get("params") or {}).items()}
        retry = step.get("retry_params")
        up = _upstream(steps, i)
        compiled = {
            "seq": i + 1,
            "app_name": step["app"],
            "depends_on_seq": None if up is None else up + 1,
            "parameters": params,
            # The runner resubmits with the WHOLE retry set, so the overlay is applied here
            # and a key the recipe did not repeat can never be dropped on retry.
            "retry_parameters": ({**params, **{k: _value(v) for k, v in retry.items()}}
                                 if retry else None),
        }
        if "id" in step:
            compiled["step_id"] = step["id"]
        if "when" in step:
            compiled["when"] = step["when"]
        out.append(compiled)
    return out


# ------------------------------------------------------------------------- select


def select(order: dict[str, Any], recipe_id: str | None = None) -> dict[str, Any]:
    """Pick a recipe for an order. Named wins; automatic selection is the `match` step."""
    if recipe_id:
        return load(recipe_id)
    raise RecipeError(
        f"no recipe named for order {order.get('id')}, and automatic selection by `match` "
        f"is not built yet; name one with --recipe")


# ------------------------------------------------------------------------- expand


def needs_dataset(steps: list[dict[str, Any]]) -> bool:
    return any(v == FROM_SPECIES for s in steps
               for key in ("parameters", "retry_parameters") for v in (s.get(key) or {}).values())


def resolve_parameters(steps: list[dict[str, Any]], dataset: dict[str, Any] | None,
                       recipe_id: str | None = None
                       ) -> tuple[list[dict[str, Any]], list[str]]:
    """Expand both templates, before anyone approves. Returns (steps, notes).

    This runs **before** the proposal is stored, not at submit time: the human who approves
    has to see the actual genome. A dataset that cannot answer raises
    `reference.ReferenceError`, so the candidate never reaches PROPOSED — refusing here is
    the point, because the alternative is a chain that runs and returns near-zero counts
    against the wrong genome, which looks like data.

    `reference_for(species)` uses the catalog's per-assay policy for this recipe when a
    family lists it, and the curated favourite farm otherwise. `same_as_previous` takes the
    same key's (already expanded) value from the one upstream step, and refuses when that
    step does not set it — the app default is not known here. Retry values are expanded too.
    """
    notes: list[str] = []
    resolved: str | None = None
    out: list[dict[str, Any]] = []
    for step in steps:
        step = dict(step)
        up = next((o for o in out if o["seq"] == step.get("depends_on_seq")), None)
        for key in ("parameters", "retry_parameters"):
            params = step.get(key)
            if not params:
                continue
            params = dict(params)
            for name, value in list(params.items()):
                if value == FROM_SPECIES:
                    if resolved is None:
                        if dataset is None:
                            raise RecipeError("reference_for(species) needs the input dataset")
                        policy = reference_policy()
                        hit = (reference.resolve_per_assay(dataset, recipe_id, policy)
                               if recipe_id and policy else None)
                        resolved, how = hit or reference.resolve_for_dataset(dataset)
                        notes.append(how)
                    params[name] = resolved
                elif value == SAME_AS_PREVIOUS:
                    source = (up or {}).get("parameters") or {}
                    if name not in source:
                        raise RecipeError(
                            f"step {step['seq']} {step['app_name']}: same_as_previous for "
                            f"{name!r}, but the upstream step does not set it")
                    params[name] = source[name]
            step[key] = params
        out.append(step)
    return out, notes
