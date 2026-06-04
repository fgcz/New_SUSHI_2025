# Backend Architecture: Layered Design

This document explains the layered architecture used in the MultiOmicsStudio FastAPI backend, how each layer handles its responsibilities, and how data flows through the system.

---

## Overview: Three Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                           ROUTES (API Layer)                         │
│                       app/api/routes/*.py                            │
│                                                                      │
│   Thin handlers - receive HTTP request, call service, return JSON    │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        SERVICES (Business Logic)                     │
│                        app/services/*.py                             │
│                                                                      │
│   Orchestrates operations, transforms data, enforces business rules  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      REPOSITORIES (Data Access)                      │
│                      app/repositories/*.py                           │
│                                                                      │
│   Raw database queries - SELECT, INSERT, UPDATE, DELETE              │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         DATABASE (SQLite)                            │
│                      storage/development.sqlite3                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Layer Responsibilities

| Layer | Location | Responsibility | Should NOT Do |
|-------|----------|----------------|---------------|
| **Routes** | `app/api/routes/` | Parse HTTP requests, validate input, return JSON | Business logic, direct SQL |
| **Services** | `app/services/` | Business logic, orchestrate repos, transform data | HTTP concerns, direct SQL |
| **Repositories** | `app/repositories/` | Database queries, model operations | Business logic, HTTP concerns |

---

## Layer 1: Routes (API Layer)

**Location:** `app/api/routes/*.py`

**Purpose:** Thin HTTP handlers that delegate to services.

### Example: `app/api/routes/datasets.py`

```python
from fastapi import APIRouter
from app.api.deps import CurrentUserDep, DatasetServiceDep

router = APIRouter()

@router.get("/{dataset_id}")
def get_dataset(
    dataset_id: int,                    # Extracted from URL path
    current_user: CurrentUserDep,       # Injected: authenticated user
    service: DatasetServiceDep,         # Injected: DatasetService instance
) -> dict:
    """Get full dataset details by ID."""
    return service.get_by_id(dataset_id)
```

### What Routes Do

1. **Define HTTP endpoints** - Method (GET/POST), path, parameters
2. **Declare dependencies** - What services/auth they need
3. **Call service methods** - Delegate actual work
4. **Return responses** - FastAPI serializes to JSON

### What Routes Should NOT Do

- ❌ Write SQL queries
- ❌ Contain business logic (if/else for business rules)
- ❌ Transform data extensively
- ❌ Call multiple services for complex orchestration

---

## Layer 2: Services (Business Logic)

**Location:** `app/services/*.py`

**Purpose:** Orchestrate repositories, enforce business rules, transform data.

### Example: `app/services/dataset.py`

```python
from app.core.exceptions import NotFoundError
from app.repositories.dataset import DatasetRepository
from app.repositories.sample import SampleRepository
from app.repositories.user import UserRepository
from omics_apps import get_runnable_apps

class DatasetService:
    def __init__(
        self,
        dataset_repo: DatasetRepository,
        user_repo: UserRepository,
        sample_repo: SampleRepository,
    ):
        self.dataset_repo = dataset_repo
        self.user_repo = user_repo
        self.sample_repo = sample_repo

    def get_by_id(self, dataset_id: int) -> dict:
        """Get full dataset details by ID including samples and applications."""

        # 1. Fetch main entity
        dataset = self.dataset_repo.get_by_id(dataset_id)
        if not dataset:
            raise NotFoundError("Dataset", dataset_id)

        # 2. Fetch related data — repos return raw models/primitives, service transforms
        user_login = None
        if dataset.user_id:
            users = self.user_repo.get_by_ids({dataset.user_id})  # list[User]
            user_login = users[0].login if users else None

        project_number = self.dataset_repo.get_project_number(dataset)
        children_ids = self.dataset_repo.get_children_ids(dataset.id)

        # Repositories return raw Sample instances; parsing and header extraction is
        # done here because it is interpretation of the key_value blob, not data access.
        raw_samples = self.sample_repo.get_by_dataset_id(dataset.id)  # list[Sample]
        samples = [parse_sample_data(s.key_value) for s in raw_samples]
        headers = extract_headers(samples)
        applications = get_runnable_apps(headers)

        # 3. Transform into API response format
        return {
            "id": dataset.id,
            "name": dataset.name,
            "user": user_login,
            "project_number": project_number,
            "children_ids": children_ids,
            "samples": samples,
            "headers": headers,
            "applications": applications,
            # ... more fields
        }
```

### What Services Do

1. **Orchestrate multiple repositories** - Gather data from different sources
2. **Enforce business rules** - Validation, authorization, constraints
3. **Transform data** - Convert DB models to API response format
4. **Raise business exceptions** - `NotFoundError`, `ForbiddenError`

### What Services Should NOT Do

- ❌ Know about HTTP (status codes, headers, request objects)
- ❌ Write raw SQL queries
- ❌ Directly access `session` - always go through repositories

---

## Layer 3: Repositories (Data Access)

**Location:** `app/repositories/*.py`

**Purpose:** Encapsulate all database queries.

### Base Repository: `app/repositories/base.py`

Provides generic CRUD operations inherited by all repositories:

```python
from typing import Generic, TypeVar
from sqlmodel import Session, select

T = TypeVar("T")

class BaseRepository(Generic[T]):
    """Base repository providing common CRUD operations."""

    def __init__(self, session: Session, model: type[T]):
        self.session = session
        self.model = model

    def get_by_id(self, id: int) -> T | None:
        """Get a single record by ID."""
        return self.session.get(self.model, id)

    def get_all(self, limit: int = 100, offset: int = 0) -> list[T]:
        """Get all records with pagination."""
        statement = select(self.model).offset(offset).limit(limit)
        return list(self.session.exec(statement).all())

    def count(self, *conditions) -> int:
        """Count records matching conditions."""
        statement = select(func.count()).select_from(self.model)
        if conditions:
            statement = statement.where(*conditions)
        return self.session.exec(statement).one()
```

### Specific Repository: `app/repositories/dataset.py`

Extends base with domain-specific queries:

```python
from sqlmodel import Session, select
from app.models import DataSet, Project
from app.repositories.base import BaseRepository

class DatasetRepository(BaseRepository[DataSet]):
    """Repository for DataSet model operations."""

    def __init__(self, session: Session):
        super().__init__(session, DataSet)

    def get_by_project_paginated(
        self,
        project_number: int,
        page: int,
        per: int,
        search: str = "",
    ) -> tuple[list[DataSet], int, int]:
        """Get paginated datasets for a project."""

        # Build query with joins and filters
        statement = (
            select(DataSet)
            .join(Project, DataSet.project_id == Project.id)
            .where(Project.number == project_number)
            .order_by(DataSet.created_at.desc())
            .offset((page - 1) * per)
            .limit(per)
        )
        datasets = list(self.session.exec(statement).all())

        # ... count query for pagination
        return datasets, total_count, total_pages

    def get_project_number(self, dataset: DataSet) -> int | None:
        """Get the project number for a dataset."""
        if dataset.project_id is None:
            return None
        project = self.session.exec(
            select(Project).where(Project.id == dataset.project_id)
        ).first()
        return project.number if project else None
```

### What Repositories Do

1. **Encapsulate SQL** - All queries in one place
2. **Return raw models or primitives** - `list[DataSet]`, `list[tuple[int, str]]`, scalars — never dicts
3. **Handle joins and filters** - Complex query logic
4. **Provide batch operations** - `get_by_ids({1, 2, 3})` returning `list[User]`

### What Repositories Should NOT Do

- ❌ Contain business logic
- ❌ Know about HTTP or API formats
- ❌ Build dicts, sort by business rules, or parse serialized blobs — that is transformation and belongs in the service

---

## Dependency Injection: Wiring It Together

**Location:** `app/api/deps.py`

FastAPI's dependency injection connects the layers.

### How Dependencies Work

```python
from typing import Annotated
from fastapi import Depends
from sqlmodel import Session

from app.core.db import get_session
from app.repositories import DatasetRepository, UserRepository, SampleRepository
from app.services import DatasetService

# Session dependency (database connection)
SessionDep = Annotated[Session, Depends(get_session)]

# Repository dependencies (need session)
def get_dataset_repository(session: SessionDep) -> DatasetRepository:
    return DatasetRepository(session)

def get_user_repository(session: SessionDep) -> UserRepository:
    return UserRepository(session)

def get_sample_repository(session: SessionDep) -> SampleRepository:
    return SampleRepository(session)

# Service dependency (needs repositories)
def get_dataset_service(
    dataset_repo: Annotated[DatasetRepository, Depends(get_dataset_repository)],
    user_repo: Annotated[UserRepository, Depends(get_user_repository)],
    sample_repo: Annotated[SampleRepository, Depends(get_sample_repository)],
) -> DatasetService:
    return DatasetService(dataset_repo, user_repo, sample_repo)

# Type alias for clean route signatures
DatasetServiceDep = Annotated[DatasetService, Depends(get_dataset_service)]
```

### Dependency Resolution Tree

When a route declares `service: DatasetServiceDep`, FastAPI resolves:

```
DatasetServiceDep
    │
    └── get_dataset_service()
            │
            ├── DatasetRepository ← get_dataset_repository()
            │       └── Session ← get_session()
            │
            ├── UserRepository ← get_user_repository()
            │       └── Session ← get_session() [same instance]
            │
            └── SampleRepository ← get_sample_repository()
                    └── Session ← get_session() [same instance]

Note: App matching uses omics_apps module directly (no repository needed)
```

All repositories share the same database session within a request.

---

## Complete Request Flow Example

**Request:** `GET /datasets/123`

```
1. HTTP Request arrives
   │
   ▼
2. FastAPI matches route: get_dataset(dataset_id=123)
   │
   ▼
3. FastAPI resolves dependencies:
   ├── CurrentUserDep → get_current_user() → CurrentUser object
   └── DatasetServiceDep → get_dataset_service() → DatasetService instance
   │
   ▼
4. Route handler executes:
   │   return service.get_by_id(123)
   │
   ▼
5. Service orchestrates:
   │   dataset = self.dataset_repo.get_by_id(123)       → SQL: SELECT * FROM datasets WHERE id=123
   │   users   = self.user_repo.get_by_ids({user_id})   → SQL: SELECT * FROM users WHERE id IN (...)
   │   raw     = self.sample_repo.get_by_dataset_id(123)→ SQL: SELECT * FROM samples WHERE data_set_id=123
   │   samples = [parse_sample_data(s.key_value) ...]   ← transformation: service parses key_value blob
   │   ... more repository calls and transformations ...
   │   return {"id": 123, "name": "...", "samples": [...]}
   │
   ▼
6. FastAPI serializes dict to JSON
   │
   ▼
7. HTTP Response: 200 OK + JSON body
```

---

## File Structure

```
app/
├── api/
│   ├── deps.py              # Dependency injection definitions
│   ├── main.py              # FastAPI app, router registration
│   └── routes/
│       ├── auth.py          # /auth/* endpoints
│       ├── datasets.py      # /datasets/* endpoints
│       ├── jobs.py          # /jobs/* endpoints
│       └── projects.py      # /projects/* endpoints
│
├── services/
│   ├── __init__.py          # Exports all services
│   ├── auth.py              # AuthService
│   ├── dataset.py           # DatasetService
│   ├── job.py               # JobService
│   └── project.py           # ProjectService
│
├── repositories/
│   ├── __init__.py          # Exports all repositories
│   ├── base.py              # BaseRepository with generic CRUD
│   ├── dataset.py           # DatasetRepository
│   ├── job.py               # JobRepository
│   ├── project.py           # ProjectRepository
│   ├── sample.py            # SampleRepository
│   ├── user.py              # UserRepository
│   └── refresh_token.py     # RefreshTokenRepository
│
omics_apps/                   # App definitions and registry
├── __init__.py              # Registry, get_app(), get_runnable_apps()
├── base.py                  # MultiOmicsApp base class
├── fastqc.py                # FastQC app definition
└── countqc.py               # CountQC app definition
│
├── models.py                # SQLModel database models
│
└── core/
    ├── config.py            # Settings from environment
    ├── db.py                # Database session management
    ├── exceptions.py        # Custom exception classes
    ├── security.py          # JWT token utilities
    └── ldap.py              # LDAP authentication
```

---

## Adding a New Feature: Checklist

When adding a new feature (e.g., "Get dataset comments"):

### 1. Repository (if new query needed)

```python
# app/repositories/dataset.py
def get_comments(self, dataset_id: int) -> list[Comment]:
    statement = select(Comment).where(Comment.dataset_id == dataset_id)
    return list(self.session.exec(statement).all())
```

### 2. Service (business logic)

```python
# app/services/dataset.py
def get_comments(self, dataset_id: int) -> list[dict]:
    dataset = self.dataset_repo.get_by_id(dataset_id)
    if not dataset:
        raise NotFoundError("Dataset", dataset_id)

    comments = self.dataset_repo.get_comments(dataset_id)
    return [{"id": c.id, "text": c.text, "created_at": c.created_at} for c in comments]
```

### 3. Route (HTTP endpoint)

```python
# app/api/routes/datasets.py
@router.get("/{dataset_id}/comments")
def get_dataset_comments(
    dataset_id: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> list[dict]:
    return service.get_comments(dataset_id)
```

---

## Testing Strategy

| Layer | Test Type | What to Test |
|-------|-----------|--------------|
| **Routes** | Integration | HTTP status codes, response format, auth |
| **Services** | Unit | Business logic with mocked repositories |
| **Repositories** | Integration | SQL queries with test database |

```python
# Test service with mocked repository
def test_get_dataset_not_found():
    mock_repo = Mock(spec=DatasetRepository)
    mock_repo.get_by_id.return_value = None

    service = DatasetService(mock_repo, ...)

    with pytest.raises(NotFoundError):
        service.get_by_id(999)
```

---

## Summary

| Principle | Implementation |
|-----------|----------------|
| **Separation of Concerns** | Each layer has one job |
| **Dependency Injection** | Services receive repositories, not create them |
| **Single Responsibility** | Routes don't do business logic, repos don't transform data |
| **Testability** | Each layer can be tested in isolation |
| **Maintainability** | Changes to DB queries don't affect routes |
