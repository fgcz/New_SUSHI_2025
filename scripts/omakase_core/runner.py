"""The chain runner — plain code, one step at a time.

Design v0.3 §10 submitted a whole chain and let SLURM sequence it. That is not
implementable here, and not because of a preference. `job_manager` hardcodes `afterany`
(`scheduler.py:65`), and when a parent has *already* failed it attaches no dependency at
all (case 7 of `scripts/job_manager_contract/wait_branch_check.py`, expected value `''`).
So SLURM will start a child whose parent failed, reading an input directory that is
missing or half-written. **Nothing below relies on SLURM to stop a chain.**

No model is involved anywhere in this file. Per design decision D4 the trigger, the timer,
every state transition and the retry decision are ordinary code; a model may only word a
proposal, break a tie between recipes, and narrate QC.

One tick polls everything in flight and then submits everything newly ready, so an
interrupted run resumes from the store rather than from memory. Until 2026-09-11 a tick did
at most one thing; steps that do not depend on each other now go out together.
"""
from __future__ import annotations

import json
from typing import Any, Callable

from . import constraints as K, store as S
from .sushi import (JOB_COMPLETED, JOB_FAILED, JOB_TERMINAL, SushiError, is_transient,
                    submit_name)

ACTOR = "omakase-core"

# A retry must ask for more than the attempt that died, or an out-of-memory job is
# resubmitted to fail identically. Doubling is blunt and predictable, which is what a
# prototype wants; a per-app table can replace it later.
RAM_MULTIPLIER = 2
DEFAULT_RAM_GB = 8


class ChainRunner:
    def __init__(self, st: S.Store, client, max_retries: int = 1,
                 log: Callable[[str], None] = print):
        self.st = st
        self.client = client
        self.max_retries = max_retries
        self.log = log

    # ------------------------------------------------------------------ helpers

    def _input_dataset_for(self, cand, step: dict) -> int:
        """Where this step reads from: the candidate's dataset, or the parent's output."""
        dep = step.get("depends_on_seq")
        if dep is None:
            return int(cand["input_dataset_id"])
        parent = self.st.latest_submission(cand["id"], int(dep))
        if parent is None or parent["state"] != S.STEP_COMPLETED:
            raise RuntimeError(
                f"step {step['seq']} depends on step {dep}, which is not COMPLETED")
        if parent["output_dataset_id"] is None:
            raise RuntimeError(f"step {dep} completed but produced no output dataset")
        return int(parent["output_dataset_id"])

    def _ready_steps(self, candidate_id: int) -> list[dict]:
        """Every step that can be submitted right now, not just the first.

        A step is ready when it is not already finished or in flight, and its dependency —
        if it has one — has reported `COMPLETED`. Steps with no dependency are all ready at
        once, which is what lets the 2026-09-10 meeting's shape run as drawn:

            FastQC ┐
            FastqScreen ┤ all three submitted in the same tick
            STAR   ┘ ──▶ FeatureCounts, only after STAR reports COMPLETED

        Before 2026-09-11 this returned one step and the chain was strictly serial. The
        results were identical; only the wall clock differed, and calling it parallel in a
        presentation would have been untrue.

        **What did not change is the thing that matters.** Readiness is still decided by the
        dependency's own `COMPLETED`, never by SLURM — `job_manager` hardcodes `afterany`
        and attaches no dependency at all to a child whose parent already failed, so a
        chain that trusted SLURM would run the child anyway.
        """
        ready = []
        for step in self.st.steps(candidate_id):
            sub = self.st.latest_submission(candidate_id, step["seq"])
            if sub is not None and sub["state"] not in (S.STEP_PENDING, S.STEP_RETRIED):
                continue  # completed, failed, or still in flight
            if not self._deps_done(candidate_id, step):
                continue
            if self._gates(candidate_id, step["seq"]):
                continue  # a person has not confirmed what this step waits for
            ready.append(step)
        return ready

    def _deps_done(self, candidate_id: int, step: dict) -> bool:
        dep = step.get("depends_on_seq")
        if dep is None:
            return True
        parent = self.st.latest_submission(candidate_id, int(dep))
        return parent is not None and parent["state"] == S.STEP_COMPLETED

    def _gates(self, candidate_id: int, seq: int | None) -> list[dict]:
        """Open checklist items at this point (constraints.py). None = before the start."""
        return K.open_items(self.st.checklist(candidate_id), seq)

    def _in_flight(self, candidate_id: int) -> list[tuple[dict, Any]]:
        """(step, submission) for every step whose jobs are with the cluster right now."""
        out = []
        for step in self.st.steps(candidate_id):
            sub = self.st.latest_submission(candidate_id, step["seq"])
            if sub is not None and sub["state"] in (S.STEP_SUBMITTED, S.STEP_RUNNING):
                out.append((step, sub))
        return out

    def _unfinished(self, candidate_id: int) -> list[dict]:
        """Steps that have not reported COMPLETED. Empty means the chain is done."""
        out = []
        for step in self.st.steps(candidate_id):
            sub = self.st.latest_submission(candidate_id, step["seq"])
            if sub is None or sub["state"] != S.STEP_COMPLETED:
                out.append(step)
        return out

    @staticmethod
    def _raise_resources(step: dict, transient_state: str) -> tuple[dict, str]:
        """Return (new params, what was raised). Honest when nothing can be raised.

        A recipe may declare `retry_parameters`, and when it does they win. That matters
        more than it looks: several SUSHI apps declare `ram` as a *selector* -- FastqcApp
        offers [15, 30, 62] -- so blindly doubling 30 would ask for 60, which is not one
        of the offered values. The recipe author knows the app's ladder; this code does
        not. Doubling is only the fallback for a recipe that says nothing.

        Only memory is raised. A TIMEOUT has no wall-clock parameter to increase through
        this API, and NODE_FAIL / PREEMPTED are worth a plain retry as they are.
        """
        params = step.get("parameters") or {}
        declared = step.get("retry_parameters")
        if declared:
            return dict(declared), "recipe's retry_parameters"
        out = dict(params)
        if transient_state == "OUT_OF_MEMORY":
            old = int(out.get("ram") or DEFAULT_RAM_GB)
            out["ram"] = old * RAM_MULTIPLIER
            return out, f"ram {old} -> {out['ram']}"
        return out, "none"

    # --------------------------------------------------------------------- submit

    def _submit_step(self, cand, step: dict, attempt: int, params: dict) -> None:
        candidate_id = int(cand["id"])
        dataset_id = self._input_dataset_for(cand, step)
        app = step.get("submit_name") or submit_name(step["app_name"])

        # Refuse before submitting rather than discovering it from a 422. The backend
        # accepts only 18 apps; the dataset endpoint advertises far more.
        try:
            submittable = self.client.submittable_app_names()
        except SushiError as exc:
            self.log(f"  ! could not read the submittable app list: {exc}")
            submittable = None
        if submittable is not None and app not in submittable:
            self.st.set_state(candidate_id, S.CHAIN_HALTED, ACTOR,
                              reason=f"{app} is not submittable on this backend "
                                     f"({len(submittable)} apps are); nothing was submitted")
            self.log(f"  HALT: {app} is not in the backend's submittable app list")
            return

        name = (f"omakase_c{candidate_id}_s{step['seq']}_{step['app_name']}"
                f"{'_retry' + str(attempt - 1) if attempt > 1 else ''}")
        try:
            res = self.client.submit(
                dataset_id=dataset_id,
                app_name=app,
                parameters=params,
                next_dataset_name=name,
                next_dataset_comment=f"OMAKASE candidate {candidate_id} step {step['seq']}",
            )
        except SushiError as exc:
            # The submit was refused or never completed. Measured 2026-09-11: with the
            # gStore copy queue stalled site-wide, the backend waited its full 900 s on
            # `g-req -w copy` and then answered **422, creating no job** -- so there is
            # nothing running and nothing to reconcile, and the honest move is to stop and
            # say why. Deliberately not retried: the retry rule is "transient by SLURM's own
            # report", and this never reached SLURM. A human re-runs once the cause is gone.
            self.st.set_state(candidate_id, S.CHAIN_HALTED, ACTOR,
                              reason=f"step {step['seq']} ({app}) could not be submitted: "
                                     f"{exc}",
                              payload={"step_seq": step["seq"], "app": app})
            self.log(f"  HALT: step {step['seq']} {app} could not be submitted: {exc}")
            return
        if res.get("dry_run"):
            self.log(f"  DRY RUN step {step['seq']} {step['app_name']} on dataset "
                     f"{dataset_id}, params {json.dumps(params, sort_keys=True)}")
            self.st.record_transition(candidate_id, S.RUNNING, S.RUNNING, ACTOR,
                                      reason=f"dry run of step {step['seq']}",
                                      payload=res.get("would_have_sent"))
            return

        self.st.open_submission(candidate_id, step["seq"], attempt,
                                res["job_ids"], res["output_dataset_id"])
        self.st.record_transition(
            candidate_id, S.RUNNING, S.RUNNING, ACTOR,
            reason=f"submitted step {step['seq']} ({step['app_name']}) attempt {attempt}",
            payload={"job_ids": res["job_ids"], "input_dataset_id": dataset_id,
                     "output_dataset_id": res["output_dataset_id"], "parameters": params})
        self.log(f"  submitted step {step['seq']} {step['app_name']} attempt {attempt}: "
                 f"jobs {res['job_ids']} -> dataset {res['output_dataset_id']}")

    # ----------------------------------------------------------------------- poll

    def _poll_step(self, cand, step: dict, sub) -> None:
        candidate_id = int(cand["id"])
        job_ids = json.loads(sub["sushi_job_ids_json"] or "[]")
        rows = [self.client.job(jid) for jid in job_ids]
        states = [r.get("status") for r in rows]

        # A step is finished only when EVERY job of it is finished. In sample mode one
        # step is one job per sample.
        if any(s not in JOB_TERMINAL for s in states):
            if sub["state"] != S.STEP_RUNNING:
                self.st.mark_submission(int(sub["id"]), S.STEP_RUNNING)
            self.log(f"  step {step['seq']} still running: {states}")
            return

        if all(s == JOB_COMPLETED for s in states):
            self.st.close_submission(int(sub["id"]), S.STEP_COMPLETED)
            self.st.record_transition(candidate_id, S.RUNNING, S.RUNNING, ACTOR,
                                      reason=f"step {step['seq']} COMPLETED",
                                      payload={"job_ids": job_ids})
            self.log(f"  step {step['seq']} COMPLETED")
            return

        # Something failed. Ask SLURM why, never the logs.
        failed = [r for r, s in zip(rows, states) if s == JOB_FAILED]
        transient, decided_by = False, "no failed job had a slurm id"
        for r in failed:
            transient, decided_by = is_transient(r.get("submit_job_id"))
            if transient:
                break

        attempt = int(sub["attempt"])
        if transient and attempt <= self.max_retries:
            params, raised = self._raise_resources(step, decided_by)
            self.st.close_submission(int(sub["id"]), S.STEP_RETRIED)
            self.st.record_transition(
                candidate_id, S.RUNNING, S.RUNNING, ACTOR,
                reason=f"step {step['seq']} failed transiently ({decided_by}); "
                       f"retrying once, raising {raised}",
                payload={"failed_job_ids": [r["id"] for r in failed],
                         "slurm_state": decided_by, "raised": raised})
            self.log(f"  step {step['seq']} FAILED transiently ({decided_by}) -> "
                     f"retry 1, raising {raised}")
            self._submit_step(cand, step, attempt + 1, params)
            return

        self.st.close_submission(int(sub["id"]), S.STEP_FAILED)
        why = (f"step {step['seq']} failed ({decided_by})"
               + ("; retry budget spent" if transient else "; not transient"))
        self.st.set_state(candidate_id, S.CHAIN_HALTED, ACTOR, reason=why,
                          payload={"failed_job_ids": [r["id"] for r in failed],
                                   "slurm_state": decided_by})
        self.log(f"  HALT: {why}. Later steps were NOT submitted.")

    # ----------------------------------------------------------------------- tick

    def tick(self, candidate_id: int) -> str:
        """Advance one candidate by at most one action. Returns its state."""
        cand = self.st.candidate(candidate_id)
        if cand is None:
            raise KeyError(f"no candidate {candidate_id}")
        state = cand["state"]

        if state in S.TERMINAL_CANDIDATE_STATES:
            return state
        if state == S.APPROVED:
            # `approve` already refuses with items open; this is the second lock, for a
            # store edited by other means.
            gates = self._gates(candidate_id, None)
            if gates:
                self.log(f"  candidate {candidate_id} is APPROVED but {len(gates)} checklist "
                         f"item(s) before the start are unconfirmed; not starting")
                return state
            self.st.set_state(candidate_id, S.RUNNING, ACTOR, reason="approved chain starting")
            cand = self.st.candidate(candidate_id)
            state = S.RUNNING
        if state != S.RUNNING:
            self.log(f"  candidate {candidate_id} is {state}; nothing to run")
            return state

        # Poll first, then submit, so a step that completes in this tick can release its
        # child in the same tick rather than costing a whole poll interval.
        for step, sub in self._in_flight(candidate_id):
            self._poll_step(cand, step, sub)
            if self.st.candidate(candidate_id)["state"] in S.TERMINAL_CANDIDATE_STATES:
                # A failure halted the chain. Siblings already with the cluster keep
                # running -- they cannot be recalled -- but nothing further is submitted,
                # which is the guarantee the whole slice exists for.
                return self.st.candidate(candidate_id)["state"]

        for step in self._ready_steps(candidate_id):
            sub = self.st.latest_submission(candidate_id, step["seq"])
            attempt = (int(sub["attempt"]) + 1) if sub is not None else 1
            self._submit_step(cand, step, attempt, step["parameters"])
            if self.st.candidate(candidate_id)["state"] in S.TERMINAL_CANDIDATE_STATES:
                return self.st.candidate(candidate_id)["state"]

        if not self._unfinished(candidate_id):
            self.st.set_state(candidate_id, S.DONE, ACTOR, reason="every step COMPLETED")
            self.log(f"  candidate {candidate_id} DONE")
            return S.DONE

        # Nothing ready and nothing in flight means a step is FAILED with the chain still
        # marked RUNNING -- reachable only if a submission was closed outside a poll.
        if not self._in_flight(candidate_id) and not self._ready_steps(candidate_id):
            waiting = [s for s in self._unfinished(candidate_id)
                       if self._deps_done(candidate_id, s) and self._gates(candidate_id, s["seq"])]
            if waiting:
                # Not stuck: a person holds the key. Everything else ran; this waits.
                for s in waiting:
                    items = self._gates(candidate_id, s["seq"])
                    self.log(f"  waiting: step {s['seq']} {s['app_name']} needs "
                             f"{len(items)} checklist item(s) confirmed: "
                             + ", ".join(str(i["idx"]) for i in items))
                return self.st.candidate(candidate_id)["state"]
            stuck = [s["seq"] for s in self._unfinished(candidate_id)]
            self.st.set_state(candidate_id, S.CHAIN_HALTED, ACTOR,
                              reason=f"step(s) {stuck} can never run: nothing is in flight "
                                     f"and no dependency will complete")
            self.log(f"  HALT: step(s) {stuck} can never run")
        return self.st.candidate(candidate_id)["state"]
