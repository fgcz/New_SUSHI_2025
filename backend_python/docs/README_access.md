# Access Control: Project-Based Restrictions

Users can only access resources belonging to projects they are members of.

---

## How It Works

1. **JWT contains project list** - When a user logs in, their token includes `projects: [1001, 1002, ...]`
2. **CurrentUser dependency** - Every protected route receives a `CurrentUser` object with this project list
3. **Access check** - Before returning data, the system verifies the resource's project is in the user's list

---

## Two Patterns

### Pattern A: Dependency-Based (Project Routes)

Used when the project number is in the URL path.

```python
# app/api/routes/projects.py
@router.get("/{project_number}/datasets")
def get_datasets(
    project_number: int,
    current_user: CurrentUserDep,
    _: RequireProjectAccess,  # Raises 403 if not in user.projects
    service: DatasetServiceDep,
) -> dict:
    return service.get_paginated(project_number, ...)
```

**Implementation:** `app/api/deps.py` → `require_project_access()`

```python
def require_project_access(project_number: int, current_user: CurrentUser):
    if settings.SKIP_AUTH:
        return
    if project_number not in current_user.projects:
        raise ForbiddenError(f"No access to project {project_number}")
```

**Protected routes:**
- `GET /projects/{project_number}/datasets`
- `GET /projects/{project_number}/jobs`
- `GET /projects/{project_number}/datasets/tree`

---

### Pattern B: Service-Based (Dataset Routes)

Used when accessing a resource directly by ID (need to look up which project it belongs to).

```python
# app/api/routes/datasets.py
@router.get("/{dataset_id}")
def get_dataset(
    dataset_id: int,
    current_user: CurrentUserDep,
    service: DatasetServiceDep,
) -> dict:
    return service.get_by_id(dataset_id, current_user)  # Check happens inside
```

**Implementation:** `app/services/dataset.py` → `_get_authorized_dataset()`

```python
def _get_authorized_dataset(self, dataset_id: int, user: CurrentUser) -> DataSet:
    dataset = self.dataset_repo.get_by_id(dataset_id)
    if not dataset:
        raise NotFoundError("Dataset", dataset_id)

    if settings.SKIP_AUTH:
        return dataset

    project_number = self.dataset_repo.get_project_number(dataset)
    if project_number is None or project_number not in user.projects:
        raise ForbiddenError(f"No access to dataset {dataset.id}")

    return dataset
```

**Protected routes:**
- `GET /datasets/{dataset_id}`
- `GET /datasets/{dataset_id}/tree`
- `GET /datasets/{dataset_id}/runnable_apps`
- `GET /datasets/{dataset_id}/samples`

---

## Request Flow

```
HTTP Request
    │
    ▼
Route extracts dataset_id from URL
    │
    ▼
FastAPI injects CurrentUser (from JWT)
    │
    ▼
service.method(dataset_id, current_user)
    │
    ▼
_get_authorized_dataset(dataset_id, user)
    ├── dataset_repo.get_by_id() → 404 if not found
    ├── SKIP_AUTH? → bypass check if true
    ├── dataset_repo.get_project_number()
    └── project_number in user.projects? → 403 if not
    │
    ▼
Return data (or error response)
```

---

## Error Responses

**404 Not Found:**
```json
{"error": {"code": "NOT_FOUND", "message": "Dataset with id '999' not found"}}
```

**403 Forbidden:**
```json
{"error": {"code": "FORBIDDEN", "message": "No access to dataset 123"}}
```

---

## Development Mode

Set `SKIP_AUTH=true` in environment to bypass all access checks. Useful for local development and testing.

---

## Adding Access Control to New Routes

For routes with project number in URL:
```python
@router.get("/{project_number}/resource")
def get_resource(
    project_number: int,
    current_user: CurrentUserDep,
    _: RequireProjectAccess,
    ...
)
```

For routes accessing resources by ID:
```python
# In service
def get_resource(self, resource_id: int, user: CurrentUser):
    resource = self._get_authorized_resource(resource_id, user)
    ...
```
