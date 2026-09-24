#!/usr/bin/env python3
"""Notifications: outbox always, send only when configured, once per event, never blocking.
rc 0 = all pass.

    python3 omakase_core/test_notify.py

No network: smtplib.SMTP is replaced by a recorder. The runner uses test_runner's fake backend.
"""
from __future__ import annotations

import email
import os
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))
for var in ("OMAKASE_NOTIFY_TO", "OMAKASE_PANEL_URL"):
    os.environ.pop(var, None)

from omakase_core import constraints as K, notify as N, runner as R, store as S  # noqa: E402
from omakase_core.test_runner import FakeClient  # noqa: E402

cases = 0
SENT: list = []


def case(name):
    global cases
    cases += 1
    print(f"  ok  {name}")


class FakeSMTP:
    fail = False

    def __init__(self, host, port, timeout=None):
        if FakeSMTP.fail:
            raise ConnectionRefusedError("relay down")

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def send_message(self, msg):
        SENT.append(msg)


N.smtplib.SMTP = FakeSMTP
TMP = Path(tempfile.mkdtemp(prefix="omakase_notify_test_"))


def fresh(name, gate=False):
    st = S.Store(TMP / f"{name}.sqlite3")
    st.listeners.append(N.Notifier(st, "test", log=lambda *_: None))
    cid, _ = st.upsert_candidate(35755, 9, "demo", "1", project_number=35611)
    st.set_steps(cid, [{"seq": 1, "app_name": "FastqcApp", "depends_on_seq": None, "parameters": {"ram": 15}},
                       {"seq": 2, "app_name": "FastqcApp", "depends_on_seq": 1, "parameters": {"ram": 15}}])
    raw = [{"assert": "species checked", "reason": "r", "at": {"before_step": "s2"}}] if gate else []
    st.set_checklist(cid, K.assess(K.compile_items(raw, [{"id": "s1", "app": "FastqcApp"},
                                                         {"id": "s2", "app": "FastqcApp"}]), [], {}))
    return st, cid


outbox = lambda st: sorted(p.name for p in (TMP / "outbox").glob(f"{Path(st.path).stem}-*"))

st, cid = fresh("a")
st.set_state(cid, S.PROPOSED, "omakase-core", "recipe demo@1")
files = outbox(st)
assert files == ["a-c1-PROPOSED.eml"] and not SENT
msg = email.message_from_bytes((TMP / "outbox" / files[0]).read_bytes())
body = msg.get_payload()
assert "PROPOSED" in msg["Subject"] and "order 35755" in msg["Subject"]
assert "approve --candidate 1" in body and "no model was involved" in body
case("PROPOSED: written to the outbox with what to do; nothing sent without recipients")
st.emit("STATE", cid, to_state="PROPOSED")
assert outbox(st) == ["a-c1-PROPOSED.eml"]
case("the same event is written once, not per call")

st, cid = fresh("b", gate=True)
st.set_state(cid, S.APPROVED, "t", "approved")
run = R.ChainRunner(st, FakeClient({}, applicable={"Fastqc"}), log=lambda *_: None)
for _ in range(6):
    run.tick(cid)
assert outbox(st) == ["b-c1-WAITING-step2.eml"], outbox(st)
body = email.message_from_bytes((TMP / "outbox" / "b-c1-WAITING-step2.eml").read_bytes()).get_payload()
assert "species checked" in body and "confirm --candidate 1" in body
case("WAITING: one notice for the gated step, however many ticks it waits")
st.confirm_item(cid, 0, "masaomi")
for _ in range(6):
    run.tick(cid)
assert "b-c1-DONE.eml" in outbox(st)
body = email.message_from_bytes((TMP / "outbox" / "b-c1-DONE.eml").read_bytes()).get_payload()
assert "-> dataset" in body
case("DONE: sent once, listing each step's output dataset")

st, cid = fresh("c")
st.set_state(cid, S.CHAIN_HALTED, "omakase-core", "step 1 failed (FAILED); not transient")
body = email.message_from_bytes((TMP / "outbox" / "c-c1-CHAIN_HALTED.eml").read_bytes()).get_payload()
assert "not transient" in body
case("CHAIN_HALTED carries the halt reason")

os.environ["OMAKASE_NOTIFY_TO"] = "a@example.org, b@example.org"
st, cid = fresh("d")
st.set_state(cid, S.PROPOSED, "omakase-core", "x")
assert len(SENT) == 1 and SENT[0]["To"] == "a@example.org, b@example.org"
case("with OMAKASE_NOTIFY_TO set the message is sent to every recipient")
FakeSMTP.fail = True
st, cid = fresh("e")
st.set_state(cid, S.PROPOSED, "omakase-core", "x")
assert (TMP / "outbox" / "e-c1-PROPOSED.failed").exists()
assert st.candidate(cid)["state"] == S.PROPOSED
case("a relay that is down is recorded (.failed) and changes nothing in the chain")
FakeSMTP.fail = False
os.environ.pop("OMAKASE_NOTIFY_TO")

st, cid = fresh("f")
st.listeners[:] = [lambda *a, **k: 1 / 0]
st.set_state(cid, S.PROPOSED, "t", "x")
assert st.candidate(cid)["state"] == S.PROPOSED
case("a listener that raises cannot undo the recorded transition")

print(f"{cases} cases, all pass")
