"""Step 2 of genome selection: ask hermes-agent (FGCZ vLLM only) to pick a species.

Called only when the plain rules (genome.py, steps 1 and 1b) cannot name one curated species.
The model never decides: it may name ONE species from a closed list or say UNKNOWN, the
answer is checked in code, and a person must confirm it before the chain may start
(genome.py turns it into a checklist hold). Decided with the user 2026-10-02.

What is sent (design §3.1 allow-list, nothing else): the Species values on the input dataset,
the species on the order's B-Fabric samples, the Sequencing Application, the library protocol
options (they name probe sets such as "Mouse Probe Set v2"), the recipe id, and the candidate
list. No sample names, no free text a customer typed, no project description.

Where it goes: hermes' api_server on 127.0.0.1, which since 2026-10-02 can only reach the FGCZ
vLLM (it runs with a credential-free HOME; scripts/omakase_deploy/lock_hermes_vllm_083.sh).
Every answer is also checked after the fact: hermes' session record must name the model the
hermes config sets as default, or the answer is discarded. Fail-closed throughout: no key,
no hermes, a timeout, an unparsable reply, a name outside the list, or another model -> no
suggestion, and the order is refused exactly as before this step existed.
"""
from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import yaml

PROMPT_VERSION = "genome-species-pick-v1"
HERMES_URL = os.environ.get("OMAKASE_HERMES_URL", "http://127.0.0.1:8642")
HERMES_HOME = Path(os.environ.get("OMAKASE_HERMES_HOME",
                                  "/srv/sushi/kairos_agent_server_dev/hermes_home"))
TIMEOUT = float(os.environ.get("OMAKASE_HERMES_TIMEOUT", "180"))

SYSTEM = (
    "You classify the organism of a sequencing dataset for a genomics facility. "
    "Answer with ONE JSON object and nothing else: "
    '{"species": "<exactly one name from CANDIDATES, or UNKNOWN>", "reason": "<one sentence>"}. '
    "Choose a candidate only if the evidence names that organism (a Latin name, a synonym, "
    "a common name, a strain, or a probe set for it). If the evidence is empty, contradictory, "
    "names several organisms, or names one that is not a candidate, answer UNKNOWN and say why. "
    "Never invent a name. Do not call any tools."
)


class AiUnavailable(RuntimeError):
    """No usable answer; the caller refuses the order as it would without this step."""


def _api_key() -> str:
    path = HERMES_HOME / ".env"
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith("API_SERVER_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError as exc:
        raise AiUnavailable(f"hermes key not readable ({exc.__class__.__name__})") from None
    raise AiUnavailable("hermes key not configured")


def expected_model() -> str:
    """The model hermes must have used: its configured default (the FGCZ vLLM)."""
    try:
        cfg = yaml.safe_load((HERMES_HOME / "config.yaml").read_text(encoding="utf-8"))
        model = (cfg.get("model") or {}).get("default")
        provider = (cfg.get("model") or {}).get("provider")
    except (OSError, yaml.YAMLError) as exc:
        raise AiUnavailable(f"hermes config not readable ({exc.__class__.__name__})") from None
    if provider != "vllm" or not model:
        raise AiUnavailable(f"hermes default provider is {provider!r}, not vllm; refusing")
    return model


def _http(method: str, path: str, key: str, body: dict | None = None,
          timeout: float = 30) -> tuple[dict, dict]:
    req = urllib.request.Request(
        HERMES_URL + path, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode() or "{}"), dict(r.headers)
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        raise AiUnavailable(f"hermes {method} {path} failed ({exc.__class__.__name__})") from None


def _parse(reply: str) -> dict:
    m = re.search(r"\{.*\}", reply or "", re.S)
    if not m:
        raise AiUnavailable("the reply holds no JSON object")
    try:
        data = json.loads(m.group(0))
    except ValueError:
        raise AiUnavailable("the reply's JSON does not parse") from None
    if not isinstance(data, dict) or not isinstance(data.get("species"), str):
        raise AiUnavailable("the reply has no 'species' string")
    return data


def suggest(evidence: dict[str, Any], candidates: list[str], key_of) -> dict[str, Any]:
    """One constrained question to hermes. Returns the checked suggestion and its provenance.

    `key_of` normalises a species name the way the engine compares them
    (reference.species_key), so "mus musculus" in a reply still means "Mus musculus".
    The returned `species` is either a member of `candidates` or "UNKNOWN".
    """
    want = expected_model()
    key = _api_key()
    user = json.dumps({"CANDIDATES": candidates, "EVIDENCE": evidence}, ensure_ascii=False)
    t0 = time.time()
    body, headers = _http("POST", "/v1/chat/completions", key, {
        "model": "hermes-agent",             # the gateway default; no provider, ever
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": user}],
    }, timeout=TIMEOUT)
    seconds = round(time.time() - t0, 1)
    reply = ((body.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
    sid = headers.get("x-hermes-session-id") or headers.get("X-Hermes-Session-Id")
    if not sid:
        raise AiUnavailable("hermes returned no session id, so the model cannot be checked")
    session, _ = _http("GET", f"/api/sessions/{sid}", key)
    used = (session.get("session") or {}).get("model")
    if used != want:
        raise AiUnavailable(f"answered by {used!r}, not the FGCZ vLLM model {want!r}; discarded")
    data = _parse(reply)
    by_key = {key_of(c): c for c in candidates}
    picked = data["species"].strip()
    species = "UNKNOWN" if picked.upper() == "UNKNOWN" else by_key.get(key_of(picked))
    if species is None:
        raise AiUnavailable(f"the model named {picked!r}, which is not a candidate; discarded")
    return {
        "species": species,
        "reason": str(data.get("reason") or "")[:300],
        "model": used,
        "session_id": sid,
        "prompt_version": PROMPT_VERSION,
        "seconds": seconds,
        "candidates": candidates,
        "evidence": evidence,
    }
