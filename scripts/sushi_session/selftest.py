#!/usr/bin/env python3
"""Self-test for sushi-session. Everything except the device approval itself.

Run:  python3 scripts/sushi_session/selftest.py

It uses a throwaway XDG_CONFIG_HOME and a throwaway keyring description, so it can never
touch a real session. No network call is made and no B-Fabric approval is needed.

The load-bearing test is `the file alone is useless`: the whole reason the key lives in the
kernel keyring rather than beside the ciphertext is that $HOME is NFS on these nodes, so
the file is expected to leave the host in backups. If that test ever fails, the design's
central claim is false and the encryption is decoration.
"""

import base64
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

# Loading `sushi-session` through SourceFileLoader would otherwise drop a __pycache__ next
# to a user-facing script. It was committed once by accident; this stops it at the source.
sys.dont_write_bytecode = True

TMP = tempfile.mkdtemp(prefix="sushi-session-selftest-")
os.environ["XDG_CONFIG_HOME"] = TMP

HERE = os.path.dirname(os.path.abspath(__file__))
# The executable has no .py suffix, so importlib cannot infer a loader from the name;
# name one explicitly rather than renaming a user-facing command to suit the test.
from importlib.machinery import SourceFileLoader

SCRIPT = os.path.join(HERE, "sushi-session")
spec = importlib.util.spec_from_loader("sushi_session", SourceFileLoader("sushi_session", SCRIPT))
ss = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ss)

# Never collide with a real key, even if this is run on a machine that has one.
ss.KEYRING_DESC = "new-sushi-session-selftest"

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  [PASS] {label}")
    else:
        failed += 1
        print(f"  [FAIL] {label}" + (f"\n         {detail}" if detail else ""))


def fake_jwt(exp_in=1800, **claims):
    def b64(d):
        return base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()
    payload = {"user_id": 1, "login": "masaomi", "type": "access",
               "exp": int(time.time()) + exp_in, **claims}
    return b64({"alg": "HS256"}) + "." + b64(payload) + ".notarealsignature"


def sample_state(jwt=None):
    return {
        "bfabric_base": "https://fgcz-bfabric-test.uzh.ch/bfabric",
        "token_url": "https://fgcz-bfabric-test.uzh.ch/bfabric/rest/oauth/token",
        "client_id": "CLI",
        "scope": "openid api:read",
        "sushi": "http://localhost:3010",
        "bfabric_access_token": "BFABRIC-ACCESS-SECRET",
        "bfabric_access_expires_at": int(time.time()) + 3600,
        "refresh_token": "BFABRIC-REFRESH-SECRET",
        "jwt": jwt or fake_jwt(),
        "login": "masaomi",
        "granted_scopes": ["openid", "api:read"],
    }


class Args:
    def __init__(self, **kw):
        self.key_mode = "keyring"
        self.key_ttl = 600
        self.__dict__.update(kw)


print("=== jwt expiry parsing ===")
check("reads exp out of a token", ss.jwt_exp(fake_jwt(1800)) > int(time.time()) + 1700)
check("an expired token reads as expired", ss.jwt_exp(fake_jwt(-100)) < int(time.time()))
check("garbage does not raise, it reads as 0", ss.jwt_exp("not-a-jwt") == 0)

keyring_ok = ss.KeyStore.keyctl_available()
print(f"\n=== kernel keyring mode (available: {keyring_ok}) ===")

if keyring_ok:
    ks = ss.KeyStore("keyring")
    ks.clear()
    salt = os.urandom(16)
    key = ks.new_key(salt, 600)
    state = sample_state()
    ss.save_state(state, ks, key, salt, 600)

    check("the state file exists", os.path.exists(ss.STATE_PATH))
    mode = oct(os.stat(ss.STATE_PATH).st_mode & 0o777)
    check("the state file is 0600", mode == "0o600", f"got {mode}")
    dmode = oct(os.stat(ss.CONFIG_DIR).st_mode & 0o777)
    check("the config directory is 0700", dmode == "0o700", f"got {dmode}")

    raw = open(ss.STATE_PATH, "rb").read()
    check("no secret appears in the file in the clear",
          b"BFABRIC-REFRESH-SECRET" not in raw and b"BFABRIC-ACCESS-SECRET" not in raw
          and state["jwt"].encode() not in raw)

    # A shape check that works WITHOUT knowing the secrets, so it can also be run against a
    # real session file. Note that grepping the whole file for `eyJ` is NOT a valid test:
    # the header line is base64 of JSON, and base64 of anything starting `{"` begins `eyJ`
    # — which is exactly why a JWT does. That false alarm cost a round trip on 2026-09-03.
    import re as _re
    head_b64, body_b64 = raw.strip().split(b"\n")
    body = base64.b64decode(body_b64)
    check("the header is the only readable part, and holds no secret",
          set(json.loads(base64.b64decode(head_b64))) == {"v", "mode", "salt"})
    check("the ciphertext contains no printable run long enough to be a token",
          not _re.findall(rb"[ -~]{12,}", body))
    check("'eyJ' appears only in the header, never in the ciphertext",
          b"eyJ" in head_b64 and b"eyJ" not in body_b64)

    back, kmode = ss.load_state(ks)
    check("it decrypts back to exactly what went in", back == state)
    check("the header records the key mode", kmode == "keyring")

    # ---- THE LOAD-BEARING TEST -------------------------------------------
    # $HOME is NFS on these nodes, so this file is expected to leave the host in a backup.
    # Dropping the key must make it unreadable.
    ks.clear()
    r = subprocess.run([sys.executable, "-c", f"""
import os, sys
os.environ["XDG_CONFIG_HOME"] = {TMP!r}
import importlib.util
from importlib.machinery import SourceFileLoader
spec = importlib.util.spec_from_loader("s", SourceFileLoader("s", {SCRIPT!r}))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.KEYRING_DESC = "new-sushi-session-selftest"
m.load_state(m.KeyStore("keyring"))
"""], capture_output=True, text=True)
    check("THE FILE ALONE IS USELESS once the key is dropped from the keyring",
          r.returncode != 0 and "key" in (r.stderr or "").lower(),
          f"rc={r.returncode} stderr={r.stderr[:200]}")

    # ---- tampering -------------------------------------------------------
    key2 = ks.new_key(salt, 600)
    ss.save_state(state, ks, key2, salt, 600)
    raw = open(ss.STATE_PATH, "rb").read()
    head, body = raw.strip().split(b"\n")
    meta = json.loads(base64.b64decode(head))
    meta["mode"] = "passphrase"          # relabel the file to steer decryption
    tampered = base64.b64encode(json.dumps(meta).encode()) + b"\n" + body + b"\n"
    open(ss.STATE_PATH, "wb").write(tampered)
    r = subprocess.run([sys.executable, "-c", f"""
import os
os.environ["XDG_CONFIG_HOME"] = {TMP!r}
import importlib.util
from importlib.machinery import SourceFileLoader
spec = importlib.util.spec_from_loader("s", SourceFileLoader("s", {SCRIPT!r}))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.KEYRING_DESC = "new-sushi-session-selftest"
m.load_state(m.KeyStore("keyring"))
"""], capture_output=True, text=True)
    check("an edited header is rejected (it is authenticated, not just carried)",
          r.returncode != 0, f"rc={r.returncode}")

    # ---- token / status --------------------------------------------------
    ks.clear()
    key3 = ks.new_key(salt, 600)
    ss.save_state(state, ks, key3, salt, 600)

    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ss.cmd_token(Args())
    check("token prints the cached JWT and makes no network call",
          buf.getvalue().strip() == state["jwt"])

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ss.cmd_status(Args())
    out = buf.getvalue()
    check("status names the login and the key protection",
          "masaomi" in out and "keyring" in out)
    check("status prints NO secret",
          "BFABRIC-REFRESH-SECRET" not in out and "BFABRIC-ACCESS-SECRET" not in out
          and state["jwt"] not in out,
          out)

    # ---- THE RENEWAL CHAIN ------------------------------------------------
    # The helper's whole claim is "one approval, then it renews itself". These cases pin
    # WHICH branch fires when, with the network stubbed: the live proof is only that the
    # stubs match reality, which the exchange endpoint's own request specs cover.
    print("\n=== renewal chain (network stubbed) ===")
    calls = []

    def fake_exchange(sushi, bf_token):
        calls.append(("exchange", bf_token))
        # A marker claim, so a renewed token is DISTINGUISHABLE from the one that was
        # already stored. fake_jwt is deterministic within the same second, so without
        # this the "--force actually replaced it" assertion compares a token with itself
        # and can never fail.
        return {"access_token": fake_jwt(1800, minted_by="exchange"),
                "granted_scopes": ["openid", "api:read"]}

    def fake_refresh(token_url, client_id, refresh_token):
        calls.append(("refresh", refresh_token))
        return {"access_token": "BFABRIC-ACCESS-2", "expires_in": 3600,
                "refresh_token": "BFABRIC-REFRESH-2"}

    real_exchange, real_refresh = ss.exchange, ss.bfabric_refresh
    ss.exchange, ss.bfabric_refresh = fake_exchange, fake_refresh

    def run_token(state):
        calls.clear()
        ss.save_state(state, ks, key3, salt, 600)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            ss.cmd_token(Args())
        return buf.getvalue().strip()

    st = sample_state(jwt=fake_jwt(-10))          # JWT dead, B-Fabric token still alive
    out = run_token(st)
    check("an expired JWT is re-exchanged, WITHOUT touching the refresh token",
          [c[0] for c in calls] == ["exchange"] and out and ss.jwt_exp(out) > int(time.time()),
          f"calls={calls}")

    # --force takes the SAME path an expiry takes, which is what makes it a usable stand-in
    # for waiting 30 minutes when proving the mechanism on a live node.
    good = sample_state(jwt=fake_jwt(1800))
    calls.clear()
    ss.save_state(good, ks, key3, salt, 600)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ss.cmd_token(Args(force=True))
    check("--force renews a session that is still good, by the same route as an expiry",
          [c[0] for c in calls] == ["exchange"]
          and buf.getvalue().strip() != good["jwt"], f"calls={calls}")

    calls.clear()
    ss.save_state(good, ks, key3, salt, 600)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ss.cmd_token(Args())
    check("...and without --force the same state is served from cache, no call at all",
          calls == [] and buf.getvalue().strip() == good["jwt"], f"calls={calls}")

    st = sample_state(jwt=fake_jwt(-10))
    st["bfabric_access_expires_at"] = int(time.time()) - 10   # both dead
    out = run_token(st)
    check("an expired B-Fabric token is refreshed first, then exchanged",
          [c[0] for c in calls] == ["refresh", "exchange"], f"calls={calls}")

    stored, _ = ss.load_state(ks)
    check("a rotated refresh token is the one kept",
          stored["refresh_token"] == "BFABRIC-REFRESH-2")
    check("the renewed B-Fabric token is kept too",
          stored["bfabric_access_token"] == "BFABRIC-ACCESS-2")

    ss.bfabric_refresh = lambda *a: None          # B-Fabric rejects the refresh token
    st = sample_state(jwt=fake_jwt(-10))
    st["bfabric_access_expires_at"] = int(time.time()) - 10
    ss.save_state(st, ks, key3, salt, 600)
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            ss.cmd_token(Args())
        rc = 0
    except SystemExit as e:
        rc = e.code
    check("a rejected refresh token asks for a new login (exit 2), it does not crash", rc == 2)

    ss.bfabric_refresh = fake_refresh
    st = sample_state(jwt=fake_jwt(-10))
    st["bfabric_access_expires_at"] = int(time.time()) - 10
    st["refresh_token"] = None                    # --no-refresh was used at login
    ss.save_state(st, ks, key3, salt, 600)
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            ss.cmd_token(Args())
        rc = 0
    except SystemExit as e:
        rc = e.code
    check("with --no-refresh, expiry asks for a new login rather than inventing one", rc == 2)

    ss.exchange, ss.bfabric_refresh = real_exchange, real_refresh

    print("\n=== logout ===")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ss.cmd_logout(Args())
    check("logout removes the file", not os.path.exists(ss.STATE_PATH))
    check("logout drops the key too", ks._keyring_get() is None)
else:
    print("  [SKIP] keyctl is not available on this host")

print("\n=== passphrase mode ===")
os.environ["SUSHI_SESSION_PASSPHRASE"] = "correct horse battery staple"
ksp = ss.KeyStore("passphrase")
salt = os.urandom(16)
key = ksp.new_key(salt, 0)
state = sample_state()
ss.save_state(state, ksp, key, salt, 0)
back, kmode = ss.load_state(ksp)
check("round-trips under a passphrase", back == state and kmode == "passphrase")

os.environ["SUSHI_SESSION_PASSPHRASE"] = "the wrong one"
r = subprocess.run([sys.executable, "-c", f"""
import os
os.environ["XDG_CONFIG_HOME"] = {TMP!r}
os.environ["SUSHI_SESSION_PASSPHRASE"] = "the wrong one"
import importlib.util
from importlib.machinery import SourceFileLoader
spec = importlib.util.spec_from_loader("s", SourceFileLoader("s", {SCRIPT!r}))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.load_state(m.KeyStore("passphrase"))
"""], capture_output=True, text=True)
check("a wrong passphrase does not decrypt", r.returncode != 0)
check("...and says so without leaking whether the file is valid",
      "did not decrypt" in (r.stderr or ""), r.stderr[:200])

# ---- THE REFRESH TOKEN'S LIFETIME -----------------------------------------------
# This number was the last unmeasured one in the whole B-Fabric login, and the reason it
# stayed unmeasured is worth pinning: the plan was "use it until it asks you to log in
# again", which measures --key-ttl (12 h by default) and not B-Fabric at all. So the
# lifetime has to be captured at the moment B-Fabric hands the token over. These cases
# fix WHICH source is believed, in what order, and that "unknown" stays an honest answer
# rather than becoming a guess.
print("=== the refresh token's lifetime ===")
now = int(time.time())

at, src = ss.refresh_expiry({"refresh_expires_in": 604800, "refresh_token": "opaque"}, now)
check("the token endpoint's own refresh_expires_in wins",
      at == now + 604800 and src == "refresh_expires_in", f"{at - now} {src}")

at, src = ss.refresh_expiry({"refresh_token_expires_in": "1209600", "refresh_token": "x"}, now)
check("the Keycloak-style spelling is accepted too, as a string",
      at == now + 1209600 and src == "refresh_token_expires_in", f"{at - now} {src}")

# If B-Fabric states no lifetime, the token itself may still say so. Worth looking rather
# than assuming opacity: an RS256 JWT is exactly what its access token turned out to be.
at, src = ss.refresh_expiry({"refresh_token": fake_jwt(3 * 86400)}, now)
check("a JWT refresh token has its own exp read when the endpoint is silent",
      abs(at - (now + 3 * 86400)) <= 2 and "jwt exp" in src, f"{at - now} {src}")

at, src = ss.refresh_expiry({"refresh_token": "wholly-opaque-string"}, now)
check("an opaque token with no stated lifetime reports UNKNOWN, it does not invent one",
      at == 0 and src.startswith("unknown"), f"{at} {src}")

# A stated lifetime must beat a claim inside the token: the endpoint is the authority on
# how long IT will honour the grant, whatever the token's own exp happens to say.
at, src = ss.refresh_expiry({"refresh_expires_in": 60, "refresh_token": fake_jwt(99999)}, now)
check("a stated lifetime outranks the token's own exp",
      at == now + 60 and src == "refresh_expires_in", f"{at - now} {src}")

check("days are rendered as days, not as 10080 minutes",
      ss.human_left(7 * 86400) == "7d 0h 0m", ss.human_left(7 * 86400))
check("a lapsed lifetime reads EXPIRED", ss.human_left(-5) == "EXPIRED")

# status must show the LIFETIME and never the token. Both halves matter: the first is the
# feature, the second is the property the whole encrypted-state design exists for.
st = sample_state()
st["refresh_expires_at"] = now + 5 * 86400
st["refresh_expiry_source"] = "refresh_expires_in"
ks.clear()
key4 = ks.new_key(salt, 600)
ss.save_state(st, ks, key4, salt, 600)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ss.cmd_status(Args())
out = buf.getvalue()
check("status reports how long the refresh token has left",
      "5d" in out and "refresh_expires_in" in out, out)
check("...and still prints no secret",
      "BFABRIC-REFRESH-SECRET" not in out, out)

# A session created before this existed has no recorded lifetime. It must not read as
# "expired", which would send someone to re-approve a login that is still perfectly good.
st2 = sample_state()
st2.pop("refresh_expires_at", None)
ss.save_state(st2, ks, key4, salt, 600)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ss.cmd_status(Args())
out = buf.getvalue()
check("a session predating this measurement says UNKNOWN, not EXPIRED",
      "UNKNOWN" in out and "EXPIRED" not in out, out)

print(f"\n{passed} passed, {failed} failed")
try:
    import shutil
    shutil.rmtree(TMP)
except Exception:
    pass
raise SystemExit(1 if failed else 0)
