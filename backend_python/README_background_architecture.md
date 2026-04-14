# Background Processing Architecture

This document explains the architectural decisions for handling background work in the SUSHI FastAPI application: job submission, SLURM monitoring, and heavy computational tasks.

---

## Overview

The application has two types of background work:

| Type | Example | Frequency | Duration |
|------|---------|-----------|----------|
| **Heavy work** | Generate 200 job scripts, write files | Per submission | 5-30 seconds |
| **Light work** | Poll SLURM, update job status | Every 5 seconds | ~100ms |

We handle these differently:

- **Heavy work** → Process Pool (isolated workers)
- **Light work** → Background Thread (the "daemon")

```
┌─────────────────────────────────────────────────────────────────┐
│                     FastAPI Application                          │
│                       (One Process)                              │
│                                                                 │
│   ┌───────────────┐   ┌───────────────┐   ┌───────────────┐    │
│   │  Main Thread  │   │ Daemon Thread │   │ Process Pool  │    │
│   │  (API)        │   │ (Job Manager) │   │ (Workers)     │    │
│   └───────────────┘   └───────────────┘   └───────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Part 1: The Daemon (Background Thread)

### What It Does

The daemon is responsible for:
1. Submitting jobs to SLURM (`sbatch`)
2. Monitoring job status (`squeue`, `sacct`)
3. Processing kill requests (`scancel`)
4. Updating the database with current status

### Why a Thread, Not a Separate Process

We chose to run the daemon as a **thread inside the FastAPI process**, not as a standalone daemon process.

#### The Alternative We Rejected

```
# Separate daemon process (NOT what we do)

┌─────────────────┐          ┌─────────────────┐
│  FastAPI        │          │  Daemon         │
│  Process        │          │  Process        │
│                 │          │                 │
│  (API only)     │          │  (SLURM work)   │
└─────────────────┘          └─────────────────┘
        │                            │
        └──────── SQLite ────────────┘

Two deployments. Two things to monitor. Two things that can fail.
```

#### What We Do Instead

```
# Background thread (what we do)

┌─────────────────────────────────────┐
│         FastAPI Process             │
│                                     │
│   ┌─────────────┐ ┌─────────────┐  │
│   │ Main Thread │ │ Daemon      │  │
│   │ (API)       │ │ Thread      │  │
│   └─────────────┘ └─────────────┘  │
│                                     │
└─────────────────────────────────────┘

One deployment. One thing to monitor. One thing that can fail.
```

#### Benefits of Thread Approach

| Aspect | Benefit |
|--------|---------|
| **Deployment** | Single unit. `systemctl restart sushi` handles everything. |
| **Monitoring** | One process to monitor. If FastAPI is up, daemon is up. |
| **Logging** | One log stream. All activity in one place. |
| **Failure recovery** | systemd restarts the process, daemon comes back automatically. |
| **Development** | Run `uvicorn` locally, daemon runs too. No extra setup. |
| **Configuration** | One config file, one environment. |

#### What Happens If FastAPI Dies?

1. Jobs already submitted to SLURM **continue running** (SLURM is independent)
2. Status updates pause temporarily
3. systemd notices and restarts FastAPI
4. Daemon thread starts again
5. Daemon queries SLURM and catches up on all status changes

**No data loss. Just a brief delay in status updates.**

#### Why This Works for SUSHI

The daemon does **light work**:
- One `squeue` call every 5 seconds
- A few database updates
- Occasional `sbatch` or `scancel` calls

This doesn't compete with the API for resources. A thread is perfectly adequate.

---

## Part 2: The Process Pool (Heavy Workers)

### What It Does

The process pool handles CPU-intensive and I/O-heavy work:
- Loading dataset with 200 samples
- Generating 200 bash scripts
- Writing scripts to filesystem
- Creating database records

### Why a Pool, Not On-Demand Spawning

#### The Alternative We Rejected

```
# On-demand spawning (NOT what we do)

Request 1 arrives → Spawn Process A → Work → Process A dies
Request 2 arrives → Spawn Process B → Work → Process B dies
Request 3 arrives → Spawn Process C → Work → Process C dies

Each request pays the cost of starting a new Python interpreter (~200-500ms).
No limit on concurrent processes.
```

#### What We Do Instead

```
# Pre-warmed pool (what we do)

Application starts → Create Worker 1, Worker 2 (they wait idle)

Request 1 arrives → Worker 1 picks it up → Work → Worker 1 ready again
Request 2 arrives → Worker 2 picks it up → Work → Worker 2 ready again
Request 3 arrives → Worker 1 picks it up (reused!) → Work → Ready again

Workers are reused. No startup cost per request.
Pool size limits concurrency automatically.
```

#### Benefits of Pool Approach

| Aspect | On-Demand | Pool |
|--------|-----------|------|
| **Startup cost per task** | 200-500ms | ~0ms |
| **Memory when idle** | 0 | ~100MB (2 workers) |
| **Memory under load** | Unbounded | Fixed |
| **Concurrent limit** | Must implement | Built-in |
| **Process reuse** | No | Yes |

#### Pool Size

We use **2 workers** because:
- Submissions are infrequent (a few per hour at peak)
- Each submission takes 5-30 seconds
- 2 workers can handle overlapping submissions
- More workers waste memory for no benefit

### Why Processes, Not Threads

The pool uses **processes** (not threads) for the heavy workers.

#### The Difference

| Thread | Process |
|--------|---------|
| Shares memory with main app | Has its own isolated memory |
| Crash can corrupt main app | Crash is contained |
| Python GIL limits parallelism | True parallelism |
| Lightweight | Heavier (but we only have 2) |

#### Crash Isolation

This is the key reason for using processes:

```
# If worker were a thread:

Worker thread crashes (bad data, bug, etc.)
         │
         ▼
Main application memory corrupted
         │
         ▼
Entire FastAPI process dies
         │
         ▼
All users affected


# With worker as process:

Worker process crashes
         │
         ▼
Worker process dies (isolated)
         │
         ▼
Pool spawns replacement worker
         │
         ▼
FastAPI continues serving other requests
         │
         ▼
Only the one failed submission affected
```

#### What Could Cause a Worker Crash?

- Malformed dataset input
- Filesystem errors (disk full, permissions)
- Memory exhaustion on very large datasets
- Bugs in script generation code

With process isolation, these failures don't bring down the entire application.

---

## Part 3: SQLite as the Coordination Layer

### How Components Communicate

The three components (API, Daemon, Workers) coordinate through SQLite:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   FastAPI   │     │   Daemon    │     │   Workers   │
│   (API)     │     │   Thread    │     │  (Pool)     │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │   writes          │   reads/writes    │   writes
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                    ┌──────┴──────┐
                    │   SQLite    │
                    │   Database  │
                    └─────────────┘
```

### The Job Table as a Queue

The `jobs` table acts as a task queue:

| status | Meaning | Who writes | Who reads |
|--------|---------|------------|-----------|
| `PENDING` | Ready to generate scripts | API | Workers |
| `CREATED` | Scripts ready, waiting for SLURM | Workers | Daemon |
| `SUBMITTED` | Sent to SLURM | Daemon | Daemon |
| `RUNNING` | Executing on cluster | Daemon | UI |
| `COMPLETED` | Finished successfully | Daemon | UI |
| `FAILED` | Execution failed | Daemon | UI |
| `KILL_ME` | User requested cancellation | API | Daemon |
| `KILLED` | Cancelled | Daemon | UI |

### Flow Example

```
1. User clicks Submit
   └── API inserts Job(status='PENDING')

2. Worker picks up job
   └── Worker: SELECT * FROM jobs WHERE status='PENDING' LIMIT 1
   └── Worker: generates scripts, writes files
   └── Worker: UPDATE jobs SET status='CREATED'

3. Daemon sees new job
   └── Daemon: SELECT * FROM jobs WHERE status='CREATED'
   └── Daemon: runs sbatch
   └── Daemon: UPDATE jobs SET status='SUBMITTED', submit_job_id=12345

4. Daemon monitors progress
   └── Daemon: runs squeue, checks job 12345
   └── Daemon: UPDATE jobs SET status='RUNNING'
   └── (later)
   └── Daemon: UPDATE jobs SET status='COMPLETED'

5. User views status
   └── API: SELECT * FROM jobs WHERE id=...
   └── Returns current status to UI
```

### Why SQLite Works Here

| Concern | Answer |
|---------|--------|
| **Concurrent writes?** | WAL mode handles this well for low concurrency |
| **Performance?** | Writes are infrequent, queries are simple |
| **Reliability?** | ACID guarantees, data survives crashes |
| **Operational overhead?** | Zero. It's a file. |

SQLite is not ideal for high-concurrency web apps, but SUSHI has:
- ~10 concurrent users maximum
- ~10 job submissions per hour at peak
- Simple queries (no complex joins under load)

This is well within SQLite's comfort zone.

### No External Message Queue Needed

We don't need Redis, RabbitMQ, or Celery because:

1. **SQLite is already there** - No new infrastructure
2. **Polling is fine** - 5-second intervals are acceptable
3. **Volume is low** - Not processing thousands of messages per second
4. **Persistence is automatic** - Jobs survive restarts (they're in the DB)

---

## Summary

### Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Daemon implementation | Background thread | Single deployment, simple operations |
| Heavy work handling | Process pool | Crash isolation, no startup overhead |
| Pool size | 2 workers | Matches workload, bounded resources |
| Worker type | Processes (not threads) | Crash isolation |
| Coordination | SQLite | Already exists, no new dependencies |
| Message queue | None (use DB) | Simplicity, adequate for scale |

### What We Avoided

| Avoided | Why |
|---------|-----|
| Separate daemon process | Operational complexity |
| On-demand process spawning | Startup overhead, unbounded concurrency |
| Thread-based workers | No crash isolation |
| Redis + Celery | Unnecessary infrastructure |
| External message queue | SQLite is sufficient |

### Operational Simplicity

Day-to-day operations involve exactly one thing:

```bash
# Deploy
git pull && systemctl restart sushi

# Check status
systemctl status sushi

# View logs
journalctl -u sushi -f

# That's it.
```

---

## Appendix: When to Reconsider

This architecture should be reconsidered if:

1. **Users increase 100x** - SQLite write contention may become an issue
2. **Submissions increase to 1000s/hour** - Pool may need scaling
3. **Multiple servers needed** - Would need external queue for coordination
4. **Jobs need complex retry logic** - Celery provides this built-in

For a lab tool with ~10 users and ~100 submissions/day, this architecture is appropriate and maintainable.
