# Database Security: Access Model and Credential Architecture

This document describes how the database is accessed, who is allowed to access it, and why the design is the way it is.

---

## The Core Principle

The database is never exposed publicly. The only way to read or write data in production is either through the FastAPI application or through an authenticated SSH session. There is no direct external database port open to the network.

This matters because application-level access control can be subverted if an attacker can reach the database directly. Network restriction + OS-level authentication is an independent, non-bypassable layer.

---

## Three Database Users

### 1. `sushi_app` — the application user

Used by the FastAPI backend at runtime. This is the user in the production connection string.

**Privileges:** `SELECT`, `INSERT`, `UPDATE`, `DELETE` on application tables.

`DELETE` is granted only on tables where user-initiated deletion is a real feature (datasets and their samples). Tables that are append-only by design (`jobs`, `audit_logs`, `refresh_tokens`, `projects`) do not grant `DELETE` to this user — a constraint enforced at the database level, not just in application code.

**Credential storage:** Injected via environment variable at deploy time. Never committed to version control. The value rotates on a schedule and on any suspected compromise.

**Where it's used:** `backend_python/.env` → `DATABASE_URI` setting → SQLAlchemy engine.

---

### 2. `sushi_migrate` — the migration user

Used only when running Alembic migrations (schema changes). Never used at application runtime.

**Privileges:** `CREATE`, `ALTER`, `DROP`, `SELECT`, `INSERT`, `UPDATE`, `DELETE` on all tables. Effectively DDL-level access.

**When it's used:** During deployments, manually by the person running the migration. After the migration completes, the session is closed and the credential is not kept in memory or on disk.

**Why it's separate:** If the application user had DDL privileges, a SQL injection or compromised token could be used to drop tables or alter schema. Keeping DDL in a separate user that is only active during intentional deployments eliminates that surface.

---

### 3. `sushi_admin` — the human break-glass user

Used by engineers for debugging, inspecting inconsistent data, or running one-off queries that the API does not expose.

**Privileges:** Full access to all tables.

**How it's accessed:** Only via SSH tunnel. The database port is not open externally. A session looks like:

```bash
ssh fgcz-h-082 -L 3306:localhost:3306
mysql -u sushi_admin -p -h 127.0.0.1 multiomicsstudio
```

**Password policy:** The password is never stored anywhere — not in a config file, not in a password manager entry that syncs to a cloud service, not in `.bash_history`. It is typed from memory or retrieved from a local-only, offline vault at the time of use. This makes credential theft via file exfiltration impossible.

**When it's used:** Debugging production data inconsistencies, verifying migrations, recovering from application bugs. Not for routine queries — if a query is needed more than once, it should become an API endpoint.

---

## How Clients Authenticate to the API

The database is accessed through the FastAPI API layer. Different clients authenticate to that API in different ways.

### Web users (MultiOmicsStudio frontend)

The browser authenticates with LDAP credentials. The API issues a short-lived JWT access token (30 minutes) and a long-lived refresh token stored in an HttpOnly cookie. Project membership is embedded in the JWT — the user can only access data belonging to projects they are a member of in LDAP.

```
Browser → POST /auth/login (LDAP credentials)
       ← JWT access token + refresh token cookie

Browser → GET /projects/1234/datasets (Authorization: Bearer <token>)
       → FastAPI decodes JWT, extracts projects list
       → checks project 1234 ∈ user.projects
       → queries DB as sushi_app
       ← dataset list
```

### Internal services (job_manager, btools, other daemons)

These processes are not humans, have no LDAP credentials, and must not be given a personal user account (that would create a persistent human-impersonation surface and complicate LDAP management).

They authenticate with machine API keys: long-lived tokens scoped to a specific set of operations (e.g., job_manager can only update job status and log paths — it cannot read datasets or delete anything). The key is passed as a `Bearer` token like a regular JWT.

**Network restriction is applied in addition to key authentication.** The API validates that requests from internal service tokens originate from known internal IP addresses or hosts. A leaked key used from an external network is rejected at the network layer before the application logic runs.

**Key storage:** In the environment of the service process, not in the codebase or any shared config file.

> **Status (2026-06):** Machine API key infrastructure is designed but not yet implemented. job_manager currently accesses the database directly. This is a known gap and the migration is planned.

---

## Development Mode

In local development, the database is SQLite and `SKIP_AUTH=true` is set in `.env`. This bypasses LDAP and JWT validation. The mock dev user is automatically given `is_employee=True`, which bypasses all project-level access checks.

This means:
- No credentials needed to run locally
- All data is accessible regardless of project membership
- `SKIP_AUTH` must never be set to `true` in any environment other than `local`

The `ENVIRONMENT` setting drives cookie security (`Secure` flag), CORS, and can be used to gate environment-specific behavior. Valid values: `local`, `staging`, `production`.

---

## Why the API Is the Sole Gateway (and Not an ORM Shared Library)

An alternative design would give every service (job_manager, btools) their own direct DB connection with `sushi_app` credentials. This was rejected because:

1. **Access control cannot be enforced.** Any service with `sushi_app` credentials can read and write any table. Application-level checks (project membership, field-level restrictions) only apply if the service implements them. A new service starts with zero access control.

2. **Audit trail is impossible.** When two services write to the same table, log correlation requires merging logs from both processes. When only the API writes, every mutation goes through one place.

3. **Schema changes require coordinating all consumers.** If a column is renamed, every service that touches that column breaks. With a single API, consumers call a versioned endpoint and the API handles schema changes internally.

4. **Credential surface grows.** Each additional direct-DB consumer is another place where `sushi_app` credentials must live.

---

## What This Model Does Not Cover (Known Gaps)

| Gap | Status |
|---|---|
| Machine API keys for job_manager / btools | Designed, not implemented |
| Audit log table and writes | Designed, not implemented |
| `sushi_app` DELETE restriction on jobs/audit_logs | Not applied yet (SQLite dev, MySQL pending) |
| MySQL production setup (currently SQLite) | Pending migration |
| Per-job scoped tokens for SLURM callback | Deferred |
