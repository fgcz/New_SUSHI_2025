#!/usr/bin/env python3
"""Genome choice: dataset -> B-Fabric samples -> the on-prem model's held suggestion.

    python3 omakase_core/test_genome.py        rc 0 = every case holds

A fixture farm and a fake hermes: no network, no model, no B-Fabric.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    __package__ = "omakase_core"

from . import constraints as K, genome as G, genome_ai as AI, reference as R  # noqa: E402
REAL_VLLM_HTTP = AI._vllm_http          # the real transport, for the off-site refusal case

TMP = Path(tempfile.mkdtemp(prefix="omakase_genome_test_"))
FARM = TMP / "farm"
MOUSE = "Mus_musculus/GENCODE/GRCm39/Annotation/Release_M37-2025-07-03"
HUMAN = "Homo_sapiens/GENCODE/GRCh38.p14/Annotation/Release_48-2025-07-03"
for rel in (MOUSE, HUMAN):
    (FARM / rel / "Genes").mkdir(parents=True)
R.FAVORITE_ROOT = FARM
cases = 0


def case(name):
    global cases
    cases += 1
    print(f"  ok  {name}")


def ds(*species):
    return {"samples": [{"Name": f"s{i}", **({} if s is None else {"Species": s})}
                        for i, s in enumerate(species)]}


def refused(fn, needle):
    try:
        fn()
    except R.ReferenceError as exc:
        assert needle.lower() in str(exc).lower(), f"{needle!r} not in {exc}"
        return str(exc)
    raise AssertionError("did not refuse")


class FakeHermes:
    def __init__(self, species="Mus musculus", fail=None):
        self.species, self.fail, self.calls = species, fail, []

    def __call__(self, evidence, candidates, key_of):
        self.calls.append((evidence, candidates))
        if self.fail:
            raise AI.AiUnavailable(self.fail)
        return {"species": self.species, "reason": "the evidence says mouse",
                "model": "DeepSeek-V4-Flash-DSpark", "session_id": "api-test",
                "prompt_version": AI.PROMPT_VERSION, "seconds": 1.0,
                "candidates": candidates, "evidence": evidence}


# --- step 1 and 1b: plain rules, no model
h = FakeHermes()
b, how, item = G.choose(ds("Mus musculus (house mouse)"), None, None, allow_ai=True, ask=h)
assert (b, item, h.calls) == (MOUSE, None, [])
case("1: the dataset's Species decides; the model is never asked")
b, how, item = G.choose(ds(None, "NA"), None, None,
                        sample_species=["Homo sapiens (human)"], allow_ai=True, ask=h)
assert b == HUMAN and item is None and "B-Fabric sample species" in how and h.calls == []
case("1b: a dataset with no Species falls back to the order's B-Fabric samples, no model")
refused(lambda: G.choose(ds(None), None, None,
                         sample_species=["Mus musculus", "Homo sapiens"], allow_ai=False),
        "2 species")
case("1b: two species on the samples is refused like two on the dataset")

# --- step 2: only when allowed, constrained, held
refused(lambda: G.choose(ds("mouse Kupffer cells"), None, None, allow_ai=False, ask=h),
        "not one of")
assert h.calls == []
case("not allowed -> the original refusal, the model is not asked")
written = []
b, how, item = G.choose(ds("mouse Kupffer cells"), None, None,
                        sample_species=["Homo sapiens"], allow_ai=True, ask=h,
                        order={"sequencingapplication": "Transcriptome Sequencing",
                               "libraryprotocoloption": ["FFPE"]},
                        record=written.append)
ev, cands = h.calls[0]
assert ev["dataset_species"] == ["mouse Kupffer cells"]
assert ev["bfabric_sample_species"] == ["Homo sapiens"]       # 1b skipped: dataset not empty
assert cands == ["Homo sapiens", "Mus musculus"]
assert set(ev) == {"dataset_species", "bfabric_sample_species", "sequencing_application",
                   "library_protocol_options", "recipe"}
case("2: the model sees only the allow-listed evidence and the curated candidates")
assert b == MOUSE and "SUGGESTED by DeepSeek" in how and len(written) == 1
assert item["idx"] == G.GENOME_ITEM and item["status"] == K.PENDING
assert item["kind"] == K.MANUAL and item["at_step_seq"] is None
assert K.open_items([item]) == [item]
case("2: a suggestion becomes a before-start hold, so approve is refused until confirmed")
msg = refused(lambda: G.choose(ds("Sus scrofa"), None, None, allow_ai=True,
                               ask=FakeHermes("UNKNOWN"), record=written.append), "UNKNOWN")
assert "not one of" in msg and len(written) == 2
case("2: UNKNOWN is a refusal that keeps the original reason, and is still recorded")
refused(lambda: G.choose(ds("Sus scrofa"), None, None, allow_ai=True,
                         ask=FakeHermes(fail="hermes down")), "no usable answer")
case("2: no answer -> refused as before the step existed")

# --- the profile switch
os.environ.pop("OMAKASE_GENOME_AI", None)
assert G.ai_allowed("test") and G.ai_allowed("production") and not G.ai_allowed("scratch")
os.environ["OMAKASE_GENOME_AI"] = "off"
assert not G.ai_allowed("test") and not G.ai_allowed("production")
os.environ.pop("OMAKASE_GENOME_AI")
case("on for test and production (2026-10-02), OMAKASE_GENOME_AI=off switches it off")

# --- a revision cannot shed the hold
steps = [{"seq": 1, "app_name": "STARApp", "parameters": {"refBuild": MOUSE}}]
try:
    G.carry_over([item], [], steps)
    raise AssertionError("an unconfirmed hold was dropped by a revision")
except R.ReferenceError as exc:
    assert str(G.GENOME_ITEM) in str(exc)
done = dict(item, status=K.CONFIRMED, confirmed_by="alice", confirmed_at="t")
kept = G.carry_over([done], [], steps)
assert kept[0]["status"] == K.CONFIRMED and "alice" in kept[0]["detail"]
assert G.carry_over([item], [], [{"seq": 1, "parameters": {"refBuild": HUMAN}}]) == []
case("revise: unconfirmed -> refused; confirmed -> kept; a person's own genome -> no hold")

# --- the hold really stops `approve`, in the store, until a named person confirms it
from . import omakase as O, recipes as RC, store as S  # noqa: E402
st = S.Store(TMP / "store.sqlite3")
cid, _ = st.upsert_candidate(order_id=1, input_dataset_id=2, recipe_id="r", recipe_version="1",
                             project_number=3, arm=S.ARM_PROPOSE)
st.set_checklist(cid, [item])
try:
    O._require_confirmed_before_start(st, cid)
    raise AssertionError("approve was not stopped by the model-suggested genome")
except RC.RecipeError as exc:
    assert "SUGGESTED by the on-prem model" in str(exc)
st.confirm_item(cid, G.GENOME_ITEM, "alice")
O._require_confirmed_before_start(st, cid)
assert st.checklist(cid)[0]["confirmed_by"] == "alice"
case("store: the hold refuses approve until a named person confirms item 3000")

# --- genome_ai: every answer is checked in code
cfg = TMP / "hermes"
cfg.mkdir()
(cfg / ".env").write_text("API_SERVER_KEY=k\n")
(cfg / "config.yaml").write_text("model:\n  default: DeepSeek-V4-Flash-DSpark\n  provider: vllm\n")
AI.HERMES_HOME = cfg


def fake_http(reply, used="DeepSeek-V4-Flash-DSpark", sid="api-1"):
    def _http(method, path, key, body=None, timeout=30):
        if method == "POST":
            assert "provider" not in body, "the engine must never name a provider"
            return ({"choices": [{"message": {"content": reply}}]},
                    {"x-hermes-session-id": sid} if sid else {})
        return {"session": {"model": used}}, {}
    return _http


C = ["Homo sapiens", "Mus musculus"]
AI._http = fake_http('{"species": "mus musculus", "reason": "probe set"}')
assert AI.suggest({}, C, R.species_key)["species"] == "Mus musculus"
case("genome_ai: a candidate in other case is mapped back; no provider is ever sent")
for reply, used, sid, needle in (
        ('{"species": "Mus musculus"}', "claude-sonnet-4-5", "api-1", "not the FGCZ vLLM"),
        ('{"species": "Danio rerio"}', "DeepSeek-V4-Flash-DSpark", "api-1", "not a candidate"),
        ("mouse, probably", "DeepSeek-V4-Flash-DSpark", "api-1", "no JSON"),
        ('{"species": "Mus musculus"}', "DeepSeek-V4-Flash-DSpark", None, "no session id")):
    AI._http = fake_http(reply, used, sid)
    try:
        AI.suggest({}, C, R.species_key)
        raise AssertionError(f"accepted: {reply} / {used} / {sid}")
    except AI.AiUnavailable as exc:
        assert needle in str(exc), (needle, str(exc))
case("genome_ai: another model, a non-candidate, no JSON, no session -> discarded")
(cfg / "config.yaml").write_text("model:\n  default: claude\n  provider: anthropic\n")
try:
    AI.expected_model()
    raise AssertionError("a non-vllm hermes default was accepted")
except AI.AiUnavailable as exc:
    assert "not vllm" in str(exc)
case("genome_ai: refuses to ask at all when hermes' default provider is not vllm")

# --- route C (2026-10-08): production asks the FGCZ vLLM directly; test keeps hermes
os.environ.pop("OMAKASE_GENOME_AI_ROUTE", None)
assert (AI.route_for("production"), AI.route_for("test")) == ("vllm", "hermes")
os.environ["OMAKASE_GENOME_AI_ROUTE"] = "hermes"
assert AI.route_for("production") == "hermes"
os.environ.pop("OMAKASE_GENOME_AI_ROUTE")
assert G.asker("production").keywords == {"route": "vllm"}
case("route_for: vllm on production, hermes on test, OMAKASE_GENOME_AI_ROUTE overrides")


def fake_vllm(reply, served=("DeepSeek-V4-Flash-DSpark",), answered="DeepSeek-V4-Flash-DSpark"):
    sent = []

    def _vllm_http(method, path, body=None, timeout=30):
        sent.append((method, path, body))
        if method == "GET":
            return {"data": [{"id": m} for m in served]}
        return {"id": "chatcmpl-1", "model": answered,
                "choices": [{"message": {"content": reply}}]}
    return _vllm_http, sent


AI._vllm_http, sent = fake_vllm('{"species": "Homo sapiens", "reason": "Human Probe Set"}')
got = AI.suggest({}, C, R.species_key, route="vllm")
assert (got["species"], got["route"], got["session_id"]) == ("Homo sapiens", "vllm", "chatcmpl-1")
assert sent[1][2]["model"] == "DeepSeek-V4-Flash-DSpark" and "provider" not in sent[1][2]
case("genome_ai vllm: asks the one served model; the answer carries route and request id")
for args, needle in (((('{"species": "Homo sapiens"}',), {"answered": "gpt-5"}), "not the FGCZ vLLM"),
                     ((('{"species": "Homo sapiens"}',), {"served": ("a", "b")}), "serves 2 models"),
                     ((('{"species": "Danio rerio"}',), {}), "not a candidate")):
    AI._vllm_http, _ = fake_vllm(*args[0], **args[1])
    try:
        AI.suggest({}, C, R.species_key, route="vllm")
        raise AssertionError(f"accepted: {args}")
    except AI.AiUnavailable as exc:
        assert needle in str(exc), (needle, str(exc))
case("genome_ai vllm: another model, an ambiguous server, a non-candidate -> discarded")
AI._vllm_http = REAL_VLLM_HTTP
AI.VLLM_URL = "https://api.anthropic.com/v1"
try:
    AI.suggest({}, C, R.species_key, route="vllm")
    raise AssertionError("an off-site host was contacted")
except AI.AiUnavailable as exc:
    assert "not an FGCZ node" in str(exc)
AI.VLLM_URL = "http://fgcz-c-056.fgcz-net.unizh.ch:8000/v1"
assert AI._ON_PREM.fullmatch("fgcz-c-056.fgcz-net.unizh.ch")
assert not AI._ON_PREM.fullmatch("fgcz-c-056.evil.example")
case("genome_ai vllm: an off-site OMAKASE_VLLM_URL is refused before any connection")

print(f"{cases} cases, all pass")
