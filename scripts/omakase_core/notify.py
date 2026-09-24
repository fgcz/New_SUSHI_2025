"""Tell a person when OMAKASE needs one, or has finished. E-mail, plain code, never blocking.

Four events, each sent at most once per candidate (the outbox file is the de-duplication):

    PROPOSED      a proposal waits for a human decision (with its open checklist items)
    WAITING       an approved chain has stopped before step N for a checklist item
    CHAIN_HALTED  the chain stopped, with the reason
    DONE          every step COMPLETED, with the output datasets

Every notification is first written to `outbox/` beside the store as an .eml file (mode
0600). That file is the record that it happened, and the whole of what happens unless
recipients are configured:

    OMAKASE_NOTIFY_TO    comma-separated addresses; unset = outbox only, nothing is sent
    OMAKASE_NOTIFY_FROM  default omakase@<this host>
    OMAKASE_SMTP         host:port, default localhost:25 (fgcz-h-083: postfix, loopback
                         only, relaying via mail.fgcz.system - measured 2026-09-24)
    OMAKASE_PANEL_URL    optional link to the control panel, added to every message

A send that fails is recorded next to the .eml (`.failed`) and never raised: a mail relay
being down must not change what the chain does. Order records are FGCZ `internal`; this
channel is internal e-mail between staff, and a message carries only the allow-listed order
fields the store already holds - no free-text customer field ever reaches the store.
"""
from __future__ import annotations

import json
import os
import smtplib
import socket
from email.message import EmailMessage
from pathlib import Path
from typing import Any

from . import constraints as K

EVENTS = ("PROPOSED", "WAITING", "CHAIN_HALTED", "DONE")


class Notifier:
    def __init__(self, store, profile_name: str, log=print):
        self.st = store
        self.profile = profile_name
        self.log = log
        self.outbox = Path(store.path).parent / "outbox"
        self.to = [a.strip() for a in os.environ.get("OMAKASE_NOTIFY_TO", "").split(",") if a.strip()]
        self.sender = os.environ.get("OMAKASE_NOTIFY_FROM") or f"omakase@{socket.getfqdn()}"
        host, _, port = os.environ.get("OMAKASE_SMTP", "localhost:25").partition(":")
        self.smtp = (host, int(port or 25))
        self.panel = os.environ.get("OMAKASE_PANEL_URL")

    # the store calls this for every event it emits
    def __call__(self, event: str, candidate_id: int, **info: Any) -> None:
        if event == "STATE" and info.get("to_state") in EVENTS:
            event = info["to_state"]
        if event not in EVENTS:
            return
        key = f"{Path(self.st.path).stem}-c{candidate_id}-{event}"
        if event == "WAITING":
            key += f"-step{info.get('seq')}"
        path = self.outbox / f"{key}.eml"
        if path.exists():
            return                                   # already told; say it once
        try:
            msg = self._message(event, candidate_id, info)
        except Exception as exc:  # noqa: BLE001 - never let a notice break the chain
            self.log(f"  notify: could not compose {event} for candidate {candidate_id}: {exc}")
            return
        self.outbox.mkdir(parents=True, exist_ok=True)
        path.write_bytes(bytes(msg))
        os.chmod(path, 0o600)
        if not self.to:
            self.log(f"  notify: {event} written to {path.name} (no OMAKASE_NOTIFY_TO; not sent)")
            return
        try:
            with smtplib.SMTP(*self.smtp, timeout=30) as smtp:
                smtp.send_message(msg)
            self.log(f"  notify: {event} sent to {len(self.to)} recipient(s)")
        except Exception as exc:  # noqa: BLE001
            path.with_suffix(".failed").write_text(f"{type(exc).__name__}: {exc}\n")
            self.log(f"  notify: {event} NOT sent ({exc}); kept in {path.name}")

    # ------------------------------------------------------------------ message

    def _message(self, event: str, cid: int, info: dict) -> EmailMessage:
        cand = self.st.candidate(cid)
        steps = self.st.steps(cid)
        checklist = self.st.checklist(cid)
        open_ = K.open_items(checklist)
        head = (f"[OMAKASE {self.profile}] candidate {cid} {event} - order {cand['order_id']}, "
                f"{cand['recipe_id']}@{cand['recipe_version']}")
        if event == "PROPOSED" and open_:
            head += f" ({len(open_)} checklist item(s) open)"
        if event == "WAITING":
            head += f" - step {info.get('seq')} waits for a confirmation"
        lines = [
            {"PROPOSED": "A proposal is waiting for a human decision. Nothing has been submitted.",
             "WAITING": "The chain is running and has stopped before one step until a person "
                        "confirms the rule(s) below. Everything else continues.",
             "CHAIN_HALTED": "The chain has stopped. Nothing further will be submitted.",
             "DONE": "Every step of the chain has COMPLETED."}[event],
            "",
            f"profile     {self.profile}",
            f"order       {cand['order_id']}   project {cand['project_number']}",
            f"dataset     {cand['input_dataset_id']}",
            f"recipe      {cand['recipe_id']}@{cand['recipe_version']}",
            f"state       {cand['state']}",
        ]
        if info.get("reason"):
            lines.append(f"reason      {info['reason']}")
        lines += ["", "chain:"]
        for s in steps:
            dep = f"after step {s['depends_on_seq']}" if s["depends_on_seq"] else "input dataset"
            sub = self.st.latest_submission(cid, s["seq"])
            out = f" -> dataset {sub['output_dataset_id']}" if sub and sub["output_dataset_id"] else ""
            state = sub["state"] if sub else "not submitted"
            lines.append(f"  {s['seq']}. {s['app_name']:<18} {dep:<16} {state}{out}")
            lines.append(f"     {json.dumps(s['parameters'], sort_keys=True)}")
        wanted = ([i for i in open_ if i["at_step_seq"] == info.get("seq")]
                  if event == "WAITING" else open_)
        if wanted:
            lines += ["", "waiting for a person:"] + [f"  {K.describe(i)}" for i in wanted]
        lines += ["", "what to do:"]
        if event == "PROPOSED":
            lines += [f"  omakase --profile {self.profile} show    --candidate {cid}",
                      f"  omakase --profile {self.profile} confirm --candidate {cid} --item N --actor you",
                      f"  omakase --profile {self.profile} approve --candidate {cid} --actor you   (or reject / revise)"]
        elif event == "WAITING":
            lines += [f"  omakase --profile {self.profile} confirm --candidate {cid} --item N --actor you"]
        else:
            lines += [f"  omakase --profile {self.profile} show --candidate {cid}"]
        if self.panel:
            lines += [f"  or the control panel: {self.panel}"]
        lines += ["", "Rules decide, humans release. This message was composed by plain code "
                      "(omakase_core/notify.py); no model was involved."]
        msg = EmailMessage()
        msg["Subject"] = head
        msg["From"] = self.sender
        msg["To"] = ", ".join(self.to) if self.to else "(outbox only - OMAKASE_NOTIFY_TO unset)"
        msg.set_content("\n".join(lines))
        return msg
