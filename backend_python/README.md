# Backend

FastAPI backend with SQLite and LDAP authentication.

## Requirements

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) (recommended) or pip
- Docker (for containerized deployment)
- SQlite database
- LDAP server

## Configuration

Configuration is split across two files with distinct responsibilities:

**`.env`** — environment-specific values that change between deployments (dev, staging, production). This file is not committed to version control. It covers infrastructure paths (`GSTORE_DIR`, `SCRATCH_DIR`), credentials (`LDAP_BIND_PASSWORD`, `JWT_SECRET_KEY`), database location, CORS origins, and operational flags like `COPY_COMMAND` (set to `cp -r` in dev, `g-req copynow` in production). Copy `.env.example` to get started.

**`app/core/config.py`** — the schema and defaults for all settings, defined as a pydantic `Settings` class. Every key that the application uses must be declared here with its type and a safe default. Values from `.env` override the defaults at runtime. This file is committed and serves as the authoritative reference for what can be configured and what the production defaults are.

The rule: if it changes between environments, it belongs in `.env`. If it is a structural default that works out of the box, it belongs in `config.py`.

## Setup

1. Copy environment variables:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your infrastructure paths and credentials.

### Option A: Run with Docker (recommended)

```bash
docker build -t backend .
docker run -p 4072:4072 --env-file .env backend
```

### Option B: Run locally (without Docker)

```bash
# Install dependencies
uv sync

# Run database migrations
uv run alembic upgrade head

# Start development server (with hot reload)
uv run fastapi dev app/main.py --port 4072 --host=0.0.0.0
```

## Development

### Linting and Formatting

```bash
# Check for lint errors
uv run ruff check .

# Auto-fix lint errors
uv run ruff check . --fix

# Format code
uv run ruff format .
```

### Type Checking

```bash
uv run mypy app/
```

### Testing

```bash
uv run pytest

# With coverage
uv run pytest --cov=app --cov-report=html
```

### Docker

```bash
# Rebuild after code changes
docker build -t backend .

# Run with --rm to auto-remove container on exit
docker run -p 4072:4072 --env-file .env --rm backend
```

## Project Structure

```
app/
├── api/           # HTTP routes and dependencies
├── core/          # Config, database, LDAP setup
├── alembic/       # Database migrations
├── models.py      # SQLModel database models
├── crud.py        # Database operations
└── main.py        # FastAPI entrypoint
```
