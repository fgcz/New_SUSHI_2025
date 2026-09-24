"""OMAKASE prototype store — the candidate, its proposed steps, and every transition.

Implements the subset of design v0.3 §12 that the first slice needs, in SQLite.
SQLite is a *prototype* choice: one writer, one file, easy to inspect by hand and to
delete. The production store is deliberately not decided here.

Two properties the design asks for and this file provides:

* **Append-only transitions.** Nothing is ever updated in `transitions`; a state change
  is a new row with timestamp, actor and reason. The current state is also cached on
  `candidates.state` so a query does not have to fold the log, but the log is the record.
* **Idempotency.** `UNIQUE(order_id, input_dataset_id, recipe_id, recipe_version)` on
  `candidates`, so re-detecting the same order is a no-op rather than a second pipeline.

Delta to §12, needed by the stepped chain runner: `submissions` carries `state`,
`attempt` and `finished_at`, so a step's own progress and its retry count live where the
step's job ids already are.
"""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

SCHEMA = """
CREATE TABLE IF NOT EXISTS candidates (
    id                INTEGER PRIMARY KEY,
    order_id          INTEGER NOT NULL,
    project_number    INTEGER,
    input_dataset_id  INTEGER NOT NULL,
    recipe_id         TEXT    NOT NULL,
    recipe_version    TEXT    NOT NULL,
    state             TEXT    NOT NULL,
    -- PROPOSE or CONTROL. A control candidate is deliberately never proposed on, so that
    -- the loop can later tell what people do unaided. Without it, every later measurement
    -- is measuring OMAKASE's own influence and cannot notice that it is.
    arm               TEXT    NOT NULL DEFAULT 'PROPOSE',
    created_at        TEXT    NOT NULL,
    updated_at        TEXT    NOT NULL,
    UNIQUE(order_id, input_dataset_id, recipe_id, recipe_version)
);

-- The label the history alone cannot give. Execution history says what was RUN; only a
-- human's verdict says what SHOULD have run. Three values on purpose: an unchanged
-- acceptance is weaker evidence than a chain someone bothered to edit into shape, and
-- collapsing them to a boolean throws that difference away.
CREATE TABLE IF NOT EXISTS verdicts (
    id                  INTEGER PRIMARY KEY,
    candidate_id        INTEGER NOT NULL REFERENCES candidates(id),
    verdict             TEXT    NOT NULL,   -- ACCEPTED | EDITED | REJECTED
    actor               TEXT    NOT NULL,
    proposed_steps_json TEXT    NOT NULL,   -- what OMAKASE offered
    final_steps_json    TEXT,               -- what the human settled on; NULL if rejected
    evidence_json       TEXT,               -- the counted frequency shown at proposal time
    note                TEXT,
    at                  TEXT    NOT NULL
);

-- The audit trail for layer 0: exactly which order fields were read.
CREATE TABLE IF NOT EXISTS order_params (
    id            INTEGER PRIMARY KEY,
    candidate_id  INTEGER NOT NULL REFERENCES candidates(id),
    field         TEXT    NOT NULL,
    value         TEXT,
    UNIQUE(candidate_id, field)
);

-- `retry_params_json` is a delta to §12. Several SUSHI apps declare `ram` as a selector
-- (FastqcApp offers [15, 30, 62]), so a retry cannot simply double the value -- the recipe
-- author states what the larger attempt should ask for. NULL means "fall back to doubling".
CREATE TABLE IF NOT EXISTS proposal_steps (
    id                INTEGER PRIMARY KEY,
    candidate_id      INTEGER NOT NULL REFERENCES candidates(id),
    seq               INTEGER NOT NULL,
    app_name          TEXT    NOT NULL,
    submit_name       TEXT,
    params_json       TEXT    NOT NULL,
    retry_params_json TEXT,
    depends_on_seq    INTEGER,
    UNIQUE(candidate_id, seq)
);

-- Append-only. Never UPDATE, never DELETE.
CREATE TABLE IF NOT EXISTS transitions (
    id            INTEGER PRIMARY KEY,
    candidate_id  INTEGER NOT NULL REFERENCES candidates(id),
    from_state    TEXT,
    to_state      TEXT    NOT NULL,
    actor         TEXT    NOT NULL,
    reason        TEXT,
    payload_json  TEXT,
    at            TEXT    NOT NULL
);

CREATE TABLE IF NOT EXISTS submissions (
    id                 INTEGER PRIMARY KEY,
    candidate_id       INTEGER NOT NULL REFERENCES candidates(id),
    step_seq           INTEGER NOT NULL,
    attempt            INTEGER NOT NULL DEFAULT 1,
    state              TEXT    NOT NULL,
    sushi_job_ids_json TEXT,
    output_dataset_id  INTEGER,
    submitted_at       TEXT,
    finished_at        TEXT,
    UNIQUE(candidate_id, step_seq, attempt)
);

-- The recipe's constraints and `when` gates for one candidate (constraints.py). Added
-- 2026-09-24; CREATE IF NOT EXISTS, so an older store gains it on its next open.
CREATE TABLE IF NOT EXISTS checklist (
    id           INTEGER PRIMARY KEY,
    candidate_id INTEGER NOT NULL REFERENCES candidates(id),
    idx          INTEGER NOT NULL,   -- position in `constraints`; 1000+N = step N's `when`
    kind         TEXT    NOT NULL,   -- MACHINE | MANUAL | WHEN
    severity     TEXT    NOT NULL,   -- refuse | hold
    at_step_seq  INTEGER,            -- NULL = before the chain's first submission
    assert_text  TEXT    NOT NULL,
    reason       TEXT,
    check_json   TEXT,
    status       TEXT    NOT NULL,   -- PASS | FAIL | PENDING | CONFIRMED
    detail       TEXT,
    confirmed_by TEXT,
    confirmed_at TEXT,
    note         TEXT,
    UNIQUE(candidate_id, idx)
);

CREATE INDEX IF NOT EXISTS idx_candidates_state ON candidates(state);
CREATE INDEX IF NOT EXISTS idx_submissions_cand ON submissions(candidate_id, step_seq);
"""

# Candidate states. The first four are v0.3 §10 unchanged; the last three are the
# delta's stepped-chain states.
ARM_PROPOSE = "PROPOSE"
ARM_CONTROL = "CONTROL"

VERDICT_ACCEPTED = "ACCEPTED"
VERDICT_EDITED = "EDITED"
VERDICT_REJECTED = "REJECTED"

DETECTED = "DETECTED"
PARAMS_OK = "PARAMS_OK"
PROPOSED = "PROPOSED"
APPROVED = "APPROVED"
RUNNING = "RUNNING"
DONE = "DONE"
CHAIN_HALTED = "CHAIN_HALTED"
SKIPPED = "SKIPPED"
CANCELLED = "CANCELLED"

TERMINAL_CANDIDATE_STATES = {DONE, CHAIN_HALTED, SKIPPED, CANCELLED}

# Step states, recorded on `submissions`.
STEP_PENDING = "PENDING"
STEP_SUBMITTED = "SUBMITTED"
STEP_RUNNING = "RUNNING"
STEP_COMPLETED = "COMPLETED"
STEP_FAILED = "FAILED"
STEP_RETRIED = "RETRIED"


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


class Store:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.path, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys = ON")
        self.db.execute("PRAGMA journal_mode = WAL")
        self.db.executescript(SCHEMA)
        # Callables (event, candidate_id, **info), told AFTER a change is recorded. Empty by
        # default: tests and read-only callers notify nobody. The CLI adds notify.Notifier.
        self.listeners: list = []

    def emit(self, event: str, candidate_id: int, **info: Any) -> None:
        for listener in self.listeners:
            try:
                listener(event, candidate_id, **info)
            except Exception:  # noqa: BLE001 - a listener must never undo a recorded change
                pass

    def close(self) -> None:
        self.db.close()

    # ---------------------------------------------------------------- candidates

    def upsert_candidate(
        self, order_id: int, input_dataset_id: int, recipe_id: str,
        recipe_version: str, project_number: int | None = None,
        arm: str = ARM_PROPOSE,
    ) -> tuple[int, bool]:
        """Return (candidate_id, created). Re-detection returns created=False.

        This is the idempotency guarantee of v0.3 §10: the same order, dataset and
        recipe version can be seen any number of times and yields one pipeline.
        """
        row = self.db.execute(
            "SELECT id FROM candidates WHERE order_id=? AND input_dataset_id=? "
            "AND recipe_id=? AND recipe_version=?",
            (order_id, input_dataset_id, recipe_id, recipe_version),
        ).fetchone()
        if row:
            return int(row["id"]), False
        ts = now_iso()
        cur = self.db.execute(
            "INSERT INTO candidates (order_id, project_number, input_dataset_id, "
            "recipe_id, recipe_version, state, arm, created_at, updated_at) "
            "VALUES (?,?,?,?,?,?,?,?,?)",
            (order_id, project_number, input_dataset_id, recipe_id, recipe_version,
             DETECTED, arm, ts, ts),
        )
        cid = int(cur.lastrowid)
        self.record_transition(cid, None, DETECTED, actor="order_watch",
                               reason="order reached status=processed")
        return cid, True

    def candidate(self, candidate_id: int) -> sqlite3.Row | None:
        return self.db.execute(
            "SELECT * FROM candidates WHERE id=?", (candidate_id,)).fetchone()

    def candidates(self, state: str | None = None) -> list[sqlite3.Row]:
        if state:
            return list(self.db.execute(
                "SELECT * FROM candidates WHERE state=? ORDER BY id", (state,)))
        return list(self.db.execute("SELECT * FROM candidates ORDER BY id"))

    def set_state(self, candidate_id: int, to_state: str, actor: str,
                  reason: str | None = None, payload: Any = None) -> None:
        row = self.candidate(candidate_id)
        if row is None:
            raise KeyError(f"no candidate {candidate_id}")
        from_state = row["state"]
        self.db.execute("UPDATE candidates SET state=?, updated_at=? WHERE id=?",
                        (to_state, now_iso(), candidate_id))
        self.record_transition(candidate_id, from_state, to_state, actor, reason, payload)
        self.emit("STATE", candidate_id, from_state=from_state, to_state=to_state, reason=reason)

    def record_transition(self, candidate_id: int, from_state: str | None,
                          to_state: str, actor: str, reason: str | None = None,
                          payload: Any = None) -> None:
        self.db.execute(
            "INSERT INTO transitions (candidate_id, from_state, to_state, actor, "
            "reason, payload_json, at) VALUES (?,?,?,?,?,?,?)",
            (candidate_id, from_state, to_state, actor, reason,
             json.dumps(payload, default=str) if payload is not None else None,
             now_iso()),
        )

    def transitions(self, candidate_id: int) -> list[sqlite3.Row]:
        return list(self.db.execute(
            "SELECT * FROM transitions WHERE candidate_id=? ORDER BY id", (candidate_id,)))

    # ------------------------------------------------------------- order params

    def set_order_params(self, candidate_id: int, params: dict[str, Any]) -> None:
        for field, value in params.items():
            self.db.execute(
                "INSERT OR REPLACE INTO order_params (candidate_id, field, value) "
                "VALUES (?,?,?)",
                (candidate_id, field, None if value is None else json.dumps(value, default=str)),
            )

    def order_params(self, candidate_id: int) -> dict[str, Any]:
        out = {}
        for r in self.db.execute(
                "SELECT field, value FROM order_params WHERE candidate_id=? ORDER BY field",
                (candidate_id,)):
            out[r["field"]] = json.loads(r["value"]) if r["value"] is not None else None
        return out

    # ------------------------------------------------------------------- steps

    def set_steps(self, candidate_id: int, steps: Iterable[dict[str, Any]]) -> None:
        """Write the proposed chain. Replaces any previous proposal for this candidate."""
        self.db.execute("DELETE FROM proposal_steps WHERE candidate_id=?", (candidate_id,))
        for step in steps:
            retry = step.get("retry_parameters")
            self.db.execute(
                "INSERT INTO proposal_steps (candidate_id, seq, app_name, submit_name, "
                "params_json, retry_params_json, depends_on_seq) VALUES (?,?,?,?,?,?,?)",
                (candidate_id, int(step["seq"]), step["app_name"], step.get("submit_name"),
                 json.dumps(step.get("parameters") or {}),
                 json.dumps(retry) if retry else None, step.get("depends_on_seq")),
            )

    def steps(self, candidate_id: int) -> list[dict[str, Any]]:
        rows = self.db.execute(
            "SELECT * FROM proposal_steps WHERE candidate_id=? ORDER BY seq", (candidate_id,))
        return [{"seq": r["seq"], "app_name": r["app_name"],
                 "submit_name": r["submit_name"],
                 "parameters": json.loads(r["params_json"]),
                 "retry_parameters": (json.loads(r["retry_params_json"])
                                      if r["retry_params_json"] else None),
                 "depends_on_seq": r["depends_on_seq"]} for r in rows]

    # ------------------------------------------------------------- submissions

    def open_submission(self, candidate_id: int, step_seq: int, attempt: int,
                        job_ids: list[int], output_dataset_id: int | None) -> int:
        cur = self.db.execute(
            "INSERT INTO submissions (candidate_id, step_seq, attempt, state, "
            "sushi_job_ids_json, output_dataset_id, submitted_at) VALUES (?,?,?,?,?,?,?)",
            (candidate_id, step_seq, attempt, STEP_SUBMITTED,
             json.dumps(job_ids), output_dataset_id, now_iso()),
        )
        return int(cur.lastrowid)

    def close_submission(self, submission_id: int, state: str) -> None:
        self.db.execute(
            "UPDATE submissions SET state=?, finished_at=? WHERE id=?",
            (state, now_iso(), submission_id))

    def mark_submission(self, submission_id: int, state: str) -> None:
        self.db.execute("UPDATE submissions SET state=? WHERE id=?", (state, submission_id))

    def submissions(self, candidate_id: int, step_seq: int | None = None) -> list[sqlite3.Row]:
        if step_seq is None:
            return list(self.db.execute(
                "SELECT * FROM submissions WHERE candidate_id=? ORDER BY step_seq, attempt",
                (candidate_id,)))
        return list(self.db.execute(
            "SELECT * FROM submissions WHERE candidate_id=? AND step_seq=? ORDER BY attempt",
            (candidate_id, step_seq)))

    def latest_submission(self, candidate_id: int, step_seq: int) -> sqlite3.Row | None:
        rows = self.submissions(candidate_id, step_seq)
        return rows[-1] if rows else None

    # ---------------------------------------------------------------- verdicts

    def record_verdict(self, candidate_id: int, verdict: str, actor: str,
                       proposed_steps, final_steps=None, evidence=None,
                       note: str | None = None) -> int:
        """The human's judgement on a proposal. Append-only, like transitions."""
        if verdict not in (VERDICT_ACCEPTED, VERDICT_EDITED, VERDICT_REJECTED):
            raise ValueError(f"verdict must be one of ACCEPTED/EDITED/REJECTED, got {verdict}")
        cur = self.db.execute(
            "INSERT INTO verdicts (candidate_id, verdict, actor, proposed_steps_json, "
            "final_steps_json, evidence_json, note, at) VALUES (?,?,?,?,?,?,?,?)",
            (candidate_id, verdict, actor, json.dumps(proposed_steps, default=str),
             json.dumps(final_steps, default=str) if final_steps is not None else None,
             json.dumps(evidence, default=str) if evidence is not None else None,
             note, now_iso()),
        )
        return int(cur.lastrowid)

    def verdicts(self, candidate_id: int | None = None) -> list[sqlite3.Row]:
        if candidate_id is None:
            return list(self.db.execute("SELECT * FROM verdicts ORDER BY id"))
        return list(self.db.execute(
            "SELECT * FROM verdicts WHERE candidate_id=? ORDER BY id", (candidate_id,)))

    # --------------------------------------------------------------- checklist

    def set_checklist(self, candidate_id: int, items) -> None:
        """Replace the candidate's checklist (a new proposal or a revision re-assesses)."""
        self.db.execute("DELETE FROM checklist WHERE candidate_id=?", (candidate_id,))
        for i in items:
            self.db.execute(
                "INSERT INTO checklist (candidate_id, idx, kind, severity, at_step_seq, "
                "assert_text, reason, check_json, status, detail) VALUES (?,?,?,?,?,?,?,?,?,?)",
                (candidate_id, i["idx"], i["kind"], i["severity"], i["at_step_seq"],
                 i["assert"], i.get("reason"),
                 json.dumps(i["check"]) if i.get("check") is not None else None,
                 i["status"], i.get("detail")))

    def checklist(self, candidate_id: int) -> list[dict[str, Any]]:
        rows = self.db.execute(
            "SELECT * FROM checklist WHERE candidate_id=? ORDER BY idx", (candidate_id,))
        return [{"idx": r["idx"], "kind": r["kind"], "severity": r["severity"],
                 "at_step_seq": r["at_step_seq"], "assert": r["assert_text"],
                 "reason": r["reason"],
                 "check": json.loads(r["check_json"]) if r["check_json"] else None,
                 "status": r["status"], "detail": r["detail"],
                 "confirmed_by": r["confirmed_by"], "confirmed_at": r["confirmed_at"],
                 "note": r["note"]} for r in rows]

    def confirm_item(self, candidate_id: int, idx: int, actor: str,
                     note: str | None = None) -> None:
        """A named person takes responsibility for one open item. Recorded, never inferred."""
        cur = self.db.execute(
            "UPDATE checklist SET status=?, confirmed_by=?, confirmed_at=?, note=? "
            "WHERE candidate_id=? AND idx=? AND status IN (?, ?) "
            "AND NOT (kind='MACHINE' AND severity='refuse')",
            ("CONFIRMED", actor, now_iso(), note, candidate_id, idx, "PENDING", "FAIL"))
        if cur.rowcount != 1:
            raise ValueError(f"candidate {candidate_id} has no open checklist item {idx}")
