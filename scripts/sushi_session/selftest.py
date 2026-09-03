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

print(f"\n{passed} passed, {failed} failed")
try:
    import shutil
    shutil.rmtree(TMP)
except Exception:
    pass
raise SystemExit(1 if failed else 0)
