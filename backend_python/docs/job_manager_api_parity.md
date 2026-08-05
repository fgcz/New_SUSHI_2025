# job_manager API parity

The job_manager (`/srv/sushi/masa_job_manager`) previously required a direct MySQL
connection to the SUSHI database to function. Every DB read and write it performs
has been replaced by an HTTP endpoint on the Python backend under `/api/internal/`.

The job_manager no longer needs a database connection, a database driver, or any
connection credentials to process jobs.

---

## Endpoint mapping

| job_manager DB call | API endpoint | Notes |
|---|---|---|
| `retrieve_jobs_with_status(cursor, status_list)` | `GET /api/internal/legacy/jobs?status=A,B,C` | Comma-separated statuses; called three times per daemon iteration with different status sets |
| `get_parent_jobs(cursor, input_dataset_id)` | `GET /api/internal/legacy/datasets/{id}/jobs` | Returns jobs whose `next_dataset_id` matches; used to resolve SLURM `--dependency=afterany:...` |
| `update_sushi_entry(cursor, job_id, 'status', ...)` | `PATCH /api/internal/legacy/jobs/{id}` | Partial update — only sent fields are written |
| `update_sushi_entry(cursor, job_id, 'submit_job_id', ...)` | same | |
| `update_sushi_entry(cursor, job_id, 'submit_command', ...)` | same | |
| `update_sushi_entry(cursor, job_id, 'stdout_path', ...)` | same | Sent as `null` to clear when a pending job is cancelled before logs are created |
| `update_sushi_entry(cursor, job_id, 'stderr_path', ...)` | same | |
| `update_sushi_entry(cursor, job_id, 'start_time', ...)` | same | |
| `update_sushi_entry(cursor, job_id, 'end_time', ...)` | same | |
| `conn.commit()` | — | Implicit inside each API call; not a separate operation |

`update_completed_samples` in `utils.py` is excluded from this table — it was
never a direct DB operation. It has always been an outbound HTTP call to the Rails
backend and remains unchanged.

---

## What can be removed from job_manager

Once the job_manager is updated to use the API:

- `src/db_manager.py` — all functions are replaced by API calls
- `get_database_connection()` and the `mysql.connector` / `sqlite3` imports
- `conn = get_database_connection(config_object)` and `conn.close()` in `run_daemon_loop`
- `conn.commit()` calls in `single_iteration`
- The `DB_HOST`, `DB_CONF_FILE`, `DB_ADAPTER`, `DB_USER`, `DB_NAME`, `SUSHI_DB_PASSWORD` environment variables
- The `mysql-connector-python` dependency from `requirements.txt` / `environment.yml`

The `cursor` parameter can be removed from `check_and_submit_new_sushi_jobs` and
`update_sushi_jobs` once those functions call the API directly.

---

## Authentication

All `/api/internal/` endpoints accept an optional `Authorization: Bearer <key>`
header. Requests without a key are currently allowed through (mock mode — any
bearer token is accepted). A real API key will be enforced once the `api_keys`
table is in place.

The job_manager should set `SUSHI_API_KEY` in its environment and send:

```
Authorization: Bearer <SUSHI_API_KEY>
```

This is the same environment variable pattern already used by btools for
`SUSHI_DB_PASSWORD`.
