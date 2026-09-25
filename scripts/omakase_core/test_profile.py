#!/usr/bin/env python3
"""Profiles keep B-Fabric TEST and PRODUCTION apart. rc 0 = every refusal still refuses.

    python3 omakase_core/test_profile.py

No network: the CLI cases use `fastqc_only` with an explicit --dataset, which derives
nothing from the backend, and every file lives under a temporary OMAKASE_ROOT.
"""
from __future__ import annotations

import importlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

ROOT = Path(tempfile.mkdtemp(prefix="omakase_profile_test_"))
os.environ["OMAKASE_ROOT"] = str(ROOT)
os.environ.pop("OMAKASE_PROFILE", None)

from omakase_core import profile as P  # noqa: E402
P = importlib.reload(P)                 # pick up the temporary root
from omakase_order_watch import watch as W  # noqa: E402
W.P = P

cases = 0


def case(name):
    global cases
    cases += 1
    print(f"  ok  {name}")


def refuses(fn, exc=P.EnvMismatch):
    try:
        fn()
    except exc:
        return True
    return False


# --- profile selection and layout
assert P.get().name == "test" and P.get().bfabric_env == "TEST"
case("default profile is test, paired with B-Fabric TEST")
assert P.get("production").may_submit is False and P.get("test").may_submit is True
case("production never submits; test may")
os.environ["OMAKASE_PROFILE"] = "production"
assert P.get().name == "production"
os.environ.pop("OMAKASE_PROFILE")
case("$OMAKASE_PROFILE selects the profile")
assert refuses(lambda: P.get("prod"), SystemExit)
case("an unknown profile name is refused, not guessed")
assert P.get("test").store_path == ROOT / "test" / "omakase.sqlite3"
assert P.get("production").state_path == ROOT / "production" / "order_watch_state.json"
assert P.get("test").events_dir != P.get("production").events_dir
case("each profile has its own home; nothing is shared but audit/ and archive/")

# --- the env check itself
test, prod = P.get("test"), P.get("production")
P.check_env("TEST", test, "x")
case("matching env passes")
assert refuses(lambda: P.check_env("PRODUCTION", test, "x"))
case("the other instance's env is refused")
assert refuses(lambda: P.check_env(None, test, "x"))
case("a file that records no env is refused")

# --- the watcher's state file and events
new = W.load_state(ROOT / "none.json", test)
assert new["env"] == "TEST"
case("a new watcher state records its env")
legacy = ROOT / "legacy_state.json"
legacy.write_text(json.dumps({"version": 1, "handled": {"40917": {"seeded": True}}, "ticks": 2}))
assert refuses(lambda: W.load_state(legacy, test))
case("a pre-2026-09-24 state without env is refused")
seeded_prod = ROOT / "prod_state.json"
seeded_prod.write_text(json.dumps({"version": 1, "env": "PRODUCTION", "handled": {}, "ticks": 0}))
assert refuses(lambda: W.load_state(seeded_prod, test))
assert W.load_state(seeded_prod, prod)["env"] == "PRODUCTION"
case("a PRODUCTION state loads under production and is refused under test")
ev = W.write_event(ROOT / "ev", {"id": 35773, "status": "processed"}, "TEST")
assert json.loads(ev.read_text())["env"] == "TEST"
case("every event records its env")


calls = []
state = {"handled": {"1": {"seeded": True},
                     "2": {"event": "/x/order_2.json"},
                     "3": {"event": "/x/order_3.json", "ingest": {"rc": 3}}}}
ran = W.ingest_pending(state, test, runner=lambda prof, path: (calls.append(path) or (3, "DECLINED: no recipe")))
assert ran == 1 and calls == ["/x/order_2.json"] and state["handled"]["2"]["ingest"]["rc"] == 3
assert W.ingest_pending(state, test, runner=lambda *a: (_ for _ in ()).throw(AssertionError)) == 0
case("--ingest reconciles: only an event without an outcome is ingested, and only once")


# --- the backend bearer: env, then the profile's own token file, then .mcp.json
from omakase_core import omakase as O  # noqa: E402
saved_082 = os.environ.pop("NEWSUSHI_TOKEN_082", None)
tf = prod.token_file
assert tf == ROOT / "production" / "backend_token"
tf.parent.mkdir(parents=True, exist_ok=True)
tf.write_text("fixture-bearer-not-real\n")
tf.chmod(0o600)
assert O.token(prod) == "fixture-bearer-not-real"
case("production reads its own token file, whitespace stripped")
os.environ["NEWSUSHI_TOKEN_082"] = "fixture-from-env"
assert O.token(prod) == "fixture-from-env"
os.environ.pop("NEWSUSHI_TOKEN_082")
case("an explicit env var still wins over the file")
tf.chmod(0o640)
assert refuses(lambda: O.token(prod), SystemExit)
case("a token file others can read is refused, not used")
tf.chmod(0o600)
tf.write_text("  \n")
assert refuses(lambda: O.token(prod), SystemExit)
case("an empty token file is refused")
tf.unlink()
if saved_082 is not None:
    os.environ["NEWSUSHI_TOKEN_082"] = saved_082


# --- the CLI
def cli(*argv, env_extra=None):
    env = dict(os.environ, **(env_extra or {}))
    r = subprocess.run([sys.executable, "-m", "omakase_core.omakase", *argv],
                       cwd=SCRIPTS, env=env, capture_output=True, text=True, timeout=120)
    return r.returncode, r.stdout + r.stderr


def event(env):
    body = {"schema": "omakase.order_processed.v1", "order": {"id": 35755, "project": {"id": 35611}}}
    if env:
        body["env"] = env
    path = ROOT / f"event_{env or 'none'}.json"
    path.write_text(json.dumps(body))
    return str(path)


rc, out = cli("ingest", "--event", event(None), "--dataset", "9", "--recipe", "fastqc_only")
assert rc == 3 and "records no B-Fabric env" in out, (rc, out)
case("ingest DECLINES an event that records no env (rc 3)")
rc, out = cli("ingest", "--event", event("PRODUCTION"), "--dataset", "9", "--recipe", "fastqc_only")
assert rc == 3 and "is from B-Fabric PRODUCTION" in out, (rc, out)
case("ingest DECLINES a PRODUCTION event under the test profile (rc 3)")
rc, out = cli("ingest", "--event", event("TEST"), "--dataset", "9", "--recipe", "fastqc_only")
assert rc == 0 and "PROPOSED" in out, (rc, out)
assert (ROOT / "test" / "omakase.sqlite3").exists()
case("a TEST event under the test profile is PROPOSED, in ~/.omakase/test/")
rc, out = cli("--profile", "production", "run", "--candidate", "1", "--dry-run")
assert rc == 3 and "never submits" in out, (rc, out)
case("run is DECLINED under production, dry run included (rc 3)")
rc, out = cli("ingest", "--event", event("TEST"), "--dataset", "9", "--recipe", "fastqc_only",
              "--base-url", "http://fgcz-h-082.fgcz-net.unizh.ch:3010")
assert rc == 2 and "not profile 'test'" in out, (rc, out)
case("a --base-url that is not the profile's backend is refused (rc 2)")

print(f"{cases} cases, all pass")
