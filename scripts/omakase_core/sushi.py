"""Talk to the Omics-Studio REST API, and ask SLURM why a job died.

Why the REST API and not the `jobs` table: it is the single sanctioned door, it enforces
the token's project scope, it behaves identically on the test and production nodes, and it
needs no database credentials. On fgcz-h-082 direct database access is forbidden outright,
so a prototype that reads the table would have to be rewritten before it could ever move.

Why `sacct` as well: the REST API reports SUSHI's own status vocabulary
(CREATED / RUNNING / COMPLETED / FAILED / …), which says *that* a job failed. Only SLURM
says *why* — and `OUT_OF_MEMORY` is a state SLURM assigns itself, which is what lets the
retry rule be mechanical instead of a log heuristic.
"""
from __future__ import annotations

import json
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

# SUSHI job states. There is no SUCCESS on this system; the success literal is COMPLETED.
JOB_COMPLETED = "COMPLETED"
JOB_FAILED = "FAILED"
JOB_TERMINAL = {JOB_COMPLETED, JOB_FAILED}

# SLURM end states that mean "try again might work". Everything else -- FAILED, CANCELLED,
# a script error -- is not transient. Measured on this cluster for 2026-09-01 onwards:
# 30 118 end states, of which OUT_OF_MEMORY 82 and TIMEOUT 5, so this path is real but rare.
SLURM_TRANSIENT = {"OUT_OF_MEMORY", "TIMEOUT", "NODE_FAIL", "PREEMPTED"}

# A submit is not a quick call. Inside it the backend runs `timeout -k 30 900 g-req -w copy`
# to move the generated scripts from /scratch to gStore, so the server is willing to wait
# **900 seconds**. Measured 2026-09-11: a copy that normally finishes in seconds sat for
# over 11 minutes. A client that gives up sooner than the server does not cancel anything --
# it just stops watching, and if the copy then succeeds the job exists with nothing in the
# store pointing at it. So the submit timeout is set past the server's own ceiling, and the
# wait is the honest cost rather than a silent orphan.
SUBMIT_TIMEOUT_SECONDS = 960


class SushiError(RuntimeError):
    pass


def submit_name(class_name: str) -> str:
    """The name `POST /api/v1/jobs` wants, from the class name applicability reports.

    Both forms are accepted -- `LegacyAppLoader.normalize` adds the `App` suffix when it
    is absent, so `Fastqc` and `FastqcApp` resolve to the same class. This exists only so
    the name matches the base-name form `/api/v1/application_configs` reports, which is
    what the submittable check compares against. A recipe step may set `submit_name`.
    """
    return class_name[:-3] if class_name.endswith("App") else class_name


class SushiClient:
    def __init__(self, base_url: str, token: str, dry_run: bool = False, timeout: int = 120):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.dry_run = dry_run
        self.timeout = timeout

    # ------------------------------------------------------------------ transport

    def _call(self, method: str, path: str, body: dict | None = None,
              timeout: int | None = None) -> Any:
        url = self.base_url + path
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token)
        if data:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout or self.timeout) as r:
                return json.loads(r.read() or b"null")
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:400]
            raise SushiError(f"{method} {path} -> HTTP {e.code}: {detail}") from e

    # ---------------------------------------------------------------------- jobs

    def submit(self, dataset_id: int, app_name: str, parameters: dict,
               next_dataset_name: str, next_dataset_comment: str = "") -> dict:
        """Submit one step. Returns {'job_ids': [...], 'output_dataset_id': int}.

        `jobs` is plural in the response because sample mode creates one job per sample
        while dataset mode creates one. The chain runner treats a step as finished only
        when *every* one of these ids is COMPLETED.
        """
        payload = {"job": {
            "dataset_id": dataset_id,
            "app_name": app_name,
            "parameters": parameters,
            "next_dataset_name": next_dataset_name,
            "next_dataset_comment": next_dataset_comment,
        }}
        if self.dry_run:
            return {"job_ids": [], "output_dataset_id": None, "dry_run": True,
                    "would_have_sent": payload}
        res = self._call("POST", "/api/v1/jobs", payload,
                         timeout=SUBMIT_TIMEOUT_SECONDS)
        jobs = res.get("jobs") or ([res["job"]] if res.get("job") else [])
        ids = [int(j["id"]) for j in jobs]
        if not ids:
            raise SushiError(f"submit returned no job ids: {res}")
        return {"job_ids": ids,
                "output_dataset_id": (res.get("output_dataset") or {}).get("id"),
                "raw": res}

    def job(self, job_id: int) -> dict:
        return self._call("GET", f"/api/v1/jobs/{job_id}")["job"]

    def job_logs(self, job_id: int) -> str | None:
        """stdout + stderr, for a human to read. Never parsed to decide a retry."""
        try:
            return self._call("GET", f"/api/v1/jobs/{job_id}/logs").get("logs")
        except SushiError:
            return None

    # ------------------------------------------------------------------ datasets

    def submittable_app_names(self) -> set[str]:
        """The apps this backend will actually accept, as base names without `App`.

        This is NOT the list `GET /api/v1/datasets/:id` returns. That one advertises
        every app the legacy catalogue considers column-compatible -- 175 for dataset 9 --
        while only **18** can be submitted: one native app plus the 17 in
        `config.legacy_apps_allowlist`. Checking the wrong list means a recipe passes
        validation and then dies on a 422 at submit time, which is how this was found.

        Measured 2026-09-10: BWA, Bowtie2, CellRanger, CellRangerMulti, CountQC, DESeq2,
        DnaBamStats, EdgeR, FastqScreen, FastqScreen10x, Fastqc, Fastqc10x, FeatureCounts,
        Kallisto, Mpileup, RnaBamStats, STAR, ScSeurat. The RNA-seq chain the meeting
        asked for -- STAR, FeatureCounts, CountQC, EdgeR -- is entirely inside it.
        """
        d = self._call("GET", "/api/v1/application_configs")
        # The entries are `{"name": "BWA"}` -- base name only, no `App` suffix.
        return {a["name"] for a in d.get("applications", []) if a.get("name")}

    def app_defaults(self, app_name: str) -> dict | None:
        """`{param: default}` as the backend resolves them, or None if it does not know the app.

        These are what a job actually receives for every key a recipe leaves out: the
        backend applies all app defaults first and overlays the submitted parameters
        (job_submission_service.rb:143-157). So a rule about a parameter has to be checked
        against this merge, not against the recipe text — a data-egress switch reached
        through an ordinary default is exactly what a recipe-only check would miss.
        Measured 2026-09-24: CellRangerMulti declares includeIntrons=true, CellRangerVersion
        defaults to Aligner/CellRanger/10.1.0 (the first option).
        """
        try:
            d = self._call("GET", f"/api/v1/application_configs/{submit_name(app_name)}")
        except SushiError as exc:
            if "404" in str(exc):
                return None
            raise
        fields = (d.get("application") or {}).get("form_fields") or []
        return {f["name"]: f.get("default_value") for f in fields if f.get("name")}

    def dataset(self, dataset_id: int) -> dict:
        return self._call("GET", f"/api/v1/datasets/{dataset_id}")

    def project_datasets(self, project_number: int, per: int = 200) -> list[dict]:
        """The project's datasets, as summaries. Cheap, and deliberately not the detail.

        Measured 2026-09-11 on project 35611: 82 datasets in one call. The summary carries
        11 fields -- `id`, `name`, `parent_id`, `bfabric_id`, `sushi_app_name`,
        `samples_count`, `completed_samples`, `children_ids`, `project_number`,
        `user_login`, `created_at` -- and **not** `order_id`. So an order lookup has to open
        each candidate; see `input_dataset.py` for why only the parentless ones are opened.
        """
        d = self._call("GET", f"/api/v1/projects/{project_number}/datasets?per={per}")
        return d.get("datasets", d) if isinstance(d, dict) else d


# --------------------------------------------------------------------------- SLURM


def slurm_states(submit_job_id: int | None) -> list[str]:
    """End states of a SLURM job, via sacct. Empty if it cannot be read.

    `--allusers` because the daemon submits as trxcopy, not as us. The `.batch` and
    `.extern` sub-steps are dropped; only the job's own state is meaningful here.
    """
    if not submit_job_id:
        return []
    try:
        out = subprocess.run(
            ["sacct", "--allusers", "-j", str(submit_job_id), "-X", "-n", "-P", "-o", "State"],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if out.returncode != 0:
        return []
    return [line.split()[0] for line in out.stdout.splitlines() if line.strip()]


def is_transient(submit_job_id: int | None) -> tuple[bool, str]:
    """Should this failure be retried? Returns (transient, the state that decided it).

    Deliberately conservative: unknown means not transient. A retry we cannot justify
    from SLURM's own report is exactly the "silent retry" that design v0.3 §11 forbids.
    """
    states = slurm_states(submit_job_id)
    if not states:
        return False, "unknown (sacct gave nothing)"
    for state in states:
        if state in SLURM_TRANSIENT:
            return True, state
    return False, ",".join(states)
