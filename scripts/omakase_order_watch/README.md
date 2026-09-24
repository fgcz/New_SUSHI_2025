# OMAKASE order watch — the `processed` trigger

Notices when a B-Fabric order's status becomes **`processed`**, and records it.

`processed` is the agreed trigger, confirmed with the team on 2026-09-10: it means
**the data is available**. A member of staff finishes QC and sets the status by
hand. Nothing downstream reacts to that today.

**This script detects and records. It never submits anything.** Choosing a
pipeline and proposing it to a bioinformatician are later stages; this one exists
so those stages have something to consume.

Read-only by construction: `client.read` is the only B-Fabric call in the file.

## Why a query, and why that is not "polling" in the bad sense

The usual objection to polling is that a change can fall between two looks. That
is true of asking *"what changed since I last looked?"*. This script does not ask
that. Every tick asks for the **complete set** of orders at `status=processed`
and subtracts the set it has already handled.

| | event sampling | set reconciliation (this) |
|---|---|---|
| watcher was down for a day | events in that window are lost | next tick still sees everything |
| the watermark | a timestamp, which can slip | our own handled-set |
| a duplicate tick | may act twice | idempotent, the diff is empty |
| B-Fabric restarts | may drop the window | irrelevant, the truth lives there |

Worth stating plainly, because it is counter-intuitive: **a push/webhook would be
the lossy option here.** A notification that fires while this process is
restarting is simply gone unless B-Fabric retries — and whether B-Fabric can push
at all is unknown. A set query cannot lose anything.

What it *does* miss: an order that enters `processed` and leaves again between two
ticks. A person sets the status by hand and a bioinformatician approval follows,
so this is not a real risk. Orders that leave the set are logged under
`left_the_set` so the churn is visible before anyone trusts the trigger.

## Load on the B-Fabric server

Measured against production on 2026-09-10:

| | |
|---|---|
| orders at `status=processed`, all time | **30** |
| whole-set query, `return_id_only=True` | **0.6–2.1 s** over four runs |
| all orders modified in ~1.5 days | 60, 2.1 s |

One tick is one id-only query. Full records are fetched only for ids that are
new, batched into a single call. At the 15-minute default that is **96 queries a
day, two to four minutes of B-Fabric time in total**.

Three things keep it considerate:

* `--interval` has a hard floor of 300 s.
* Each sleep is jittered ±10 %, so restarts and parallel instances cannot settle
  into lockstep.
* A failed tick backs off (doubling, capped at an hour) instead of retrying at
  once.

## First run

**Seed before anything else**, or the first tick treats all 30 existing orders as
new:

```bash
python watch.py --seed             # adopt the current backlog, write no events
python watch.py --once             # one tick; should be quiet
python watch.py --status           # what it knows
python watch.py                    # loop at 900 s
```

If you forget, the `--max-new` guard (default 10) stops the tick and writes
nothing rather than firing a burst. That guard also catches a lost state file and
a change in the status vocabulary.

## Output

One JSON file per detected order, mode 0600, under `~/.omakase/<profile>/events/` — `test` (B-Fabric TEST, the default) or `production` (B-Fabric PRODUCTION); see `omakase_core/profile.py`. Since 2026-09-24 every event and the state file carry `"env"`, and a state file from the other instance, or one without `env`, is refused:

```json
{
  "schema": "omakase.order_processed.v1",
  "detected_at": "2026-09-10T11:19:22+02:00",
  "trigger_status": "processed",
  "order": {
    "id": 40917,
    "status": "processed",
    "statusmodified": "2026-06-10T17:34:56.191",
    "statusmodifiedby": {"classname": "user", "id": 6921},
    "project": {"classname": "project", "id": 2220},
    "servicetype": {"classname": "servicetype", "id": 164},
    "sequencingapplication": "Transcriptome Sequencing",
    "libraryprotocol": "Covaris truCOVER Total RNA Library Prep",
    "instrument": "Illumina NovaSeq X Plus",
    "numberofsamples": 24, "countsamples": 145, "countdatasets": 7
  }
}
```

`statusmodified` and `statusmodifiedby` are carried deliberately: they say **when
and by whom**, which is the provenance the rest of OMAKASE currently lacks.

Free-text customer fields (billing, requester, order label) are **not** copied.
Order records are FGCZ `internal`, and the pipeline-choice stage does not need
them. Console output is ids and timings only.

## What the B-Fabric API actually allows

Measured 2026-09-10 with bfabricPy 1.13.29:

| | |
|---|---|
| `status` returned on `order` | yes — the endpoint returns 50 fields |
| `status` usable as a **filter** | yes |
| valid values | a fixed enum of ~40: `ACCEPTED, ANALYZED, ANALYZING, ARRIVED, …, PROCESSED, PROCESSING, PROCESSINGFAILED, …`; an invalid value is rejected with the list |
| `statusmodified`, `statusmodifiedby` | returned |
| `modifiedafter`, `modifiedbefore` | work |
| `statusmodifiedafter` | **does not exist** (`TypeNotFound`) |
| `projectid` filter | works — `--project` uses it |
| `status` as a list | works |
| webhook / status-change hook | none found in the bfabricPy documentation; B-Fabric's `externaljob` mechanism is bound to workunits and applications, not to order status |

## Credentials

Uses `~/.bfabricpy.yml`. For the prototype the existing `gfeeder` login is
agreed. A dedicated service account for unattended production operation is a
separate team decision, already on the list of things to ask FGCZ.

## Not done here

* Choosing a pipeline from the metadata in the event. That is the next stage and
  needs the recipe catalogue, which by standing decision a bioinformatician
  writes by hand.
* Anything at all on the SUSHI side. No job is created, no database is touched.
* Deciding whether a submitted job finished correctly. That is the second open
  question, still unanswered.
