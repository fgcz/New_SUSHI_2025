# Backend

FastAPI backend with MariaDB and LDAP authentication.

## Requirements

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) (recommended) or pip
- Docker (for containerized deployment)
- MariaDB database
- LDAP server

## Setup

1. Copy environment variables:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your MariaDB and LDAP credentials.

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
