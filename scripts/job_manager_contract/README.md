# job_manager dependency-contract check

New SUSHI writes `jobs` rows; the **job_manager daemon** (a separate Python project, not
this repo) decides how those rows reach SLURM. The chaining behaviour New SUSHI depends on
lives entirely in that daemon's `_resolve_dependency`, and nothing in this repo's test suite
can reach it. This is the only executable check of that contract that exists anywhere.

It calls the **real deployed** `src/scheduler._resolve_dependency` and substitutes only what
`get_parent_jobs` returns — exactly what a different DB state would do. It therefore makes
**no database write and submits no cluster job**: the DB driver is stubbed with a connect
that raises, the cursor passed in is `None`, and the log dir is redirected to a temp dir so
importing the module cannot append to the shared `/misc/fgcz01/sushi/job_logs/` files.

## Run

```bash
python3 scripts/job_manager_contract/wait_branch_check.py            # rc 0 = contract holds
JOB_MANAGER_DIR=/path/to/job_manager python3 scripts/job_manager_contract/wait_branch_check.py
```

Default checkout is `/srv/sushi/masa_job_manager`. Exit code is 0 only if every case matches.

## What the eight cases pin

| parents | expected |
|---------|----------|
| all COMPLETED | no dependency |
| all RUNNING with SLURM ids | `--dependency=afterany:<id>:<id>` |
| all CREATED, no SLURM id yet | `WAIT` |
| mixed submitted + CREATED | `WAIT` (all-or-nothing) |
| a `WAITING_FOR_METHODS` row beside submitted siblings | `WAIT` (the realistic trigger) |
| a parent wedged in `SCRIPT_NOT_FOUND_TRY_1` | `WAIT` (active via the `startswith` check) |
| parent **FAILED** | **no dependency — the child is released** |
| no producing jobs at all (root / B-Fabric dataset) | no dependency |

## The two findings worth remembering

1. **The WAIT branch had never fired in production** before this was written. The cases above
   are what made it reachable on paper; the realistic trigger is a legacy `methods` row
   parked next to already-submitted siblings.
2. **`afterany` releases a child even when the parent FAILED** (hardcoded, `scheduler.py:65`).
   Row 7 pins that as *current documented behaviour*, not as desirable behaviour — it is the
   silent failure mode. Legacy shares it and New SUSHI adds no compensating gate. If a gate
   is ever added, row 7 is the case that must change.

## Result 2026-08-13

All 8 cases PASS against the deployed daemon (`/srv/sushi/masa_job_manager/src/scheduler.py`).

Unrelated but relevant when reading job status on fgcz-h-083: **two** job_manager daemons are
running there, so every job is sbatched twice and one twin fails on the gStore destination
collision. `jobs.status` is last-writer-wins and therefore unreliable — judge by
`sacct --allusers` plus the result directory. Needs rdomi/trxcopy to stop the stale one.
