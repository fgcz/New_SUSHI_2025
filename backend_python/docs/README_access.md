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

### Pattern B (variant): Job routes

Jobs do not have a project number in their URL. The project is resolved by walking `job → dataset → project`. The check is identical to Pattern B, but if the project cannot be resolved (orphaned job with no linked dataset), non-employees are denied rather than allowed.

**Implementation:** `app/services/job.py` → `_get_authorized_job()`

**Protected routes:**
- `GET /jobs/{job_id}`
- `GET /jobs/{job_id}/script`
- `GET /jobs/{job_id}/logs`

**Employees** (`is_employee=True` in JWT) bypass the project membership check on all patterns. This represents B-Fabric admin users who need cross-project visibility.

---

### Pattern C: Scope-Based Access on a Single Route (`GET /jobs`)

Some resources need to serve two completely different audiences from the same URL: regular users who see only their project's data, and employees who see everything. The `GET /api/jobs` endpoint is the canonical example of this pattern.

#### The design decision

Rather than creating a separate `/api/admin/jobs` route for employees and `/api/projects/{n}/jobs` for users, a single `GET /api/jobs` endpoint accepts an optional `?project=` query parameter. The presence or absence of that parameter determines both the scope of the query and which auth check is applied.

```
GET /api/jobs               → employee only, returns all jobs across all projects
GET /api/jobs?project=1001  → any user, returns jobs for project 1001 (membership checked)
```

The service method handles both cases in one place:

```python
def get_jobs(self, project: int | None, caller: CurrentUser) -> dict:
    if project is None:
        # Global view — employees only
        if not settings.SKIP_AUTH and not caller.is_employee:
            raise ForbiddenError("Global job listing requires employee access")
        return self.job_repo.get_all_paginated(...)
    else:
        # Project-scoped view — membership required
        require_project_access(project, caller)
        dataset_ids = self.project_repo.get_dataset_ids_by_number(project)
        return self.job_repo.get_by_project_paginated(dataset_ids, ...)
```

#### Why a single route makes the admin check more consistent

With two separate routes (`/admin/jobs` and `/projects/{n}/jobs`), the employee check must be remembered and applied to each admin route independently. Miss it on one, and that route becomes unguarded. With the single-route pattern, the admin check is structural: if `project` is absent, the employee branch runs unconditionally. There is no parallel route where the check can be forgotten, because there is no parallel route.

As the jobs section grows — filters, exports, statistics — those features are added as query parameters to the same endpoint. The employee check is always at the top of the same method. It cannot be skipped by adding a new route that omits it.

#### What the frontend does

The frontend reads `is_employee` from the JWT (available via `GET /api/auth/me`) and chooses which form of the URL to call:

```
is_employee = true  →  GET /api/jobs              (global admin view)
is_employee = false →  GET /api/jobs?project=1001  (project-scoped user view)
```

This is a routing decision in the frontend, not a security boundary. The frontend makes this distinction for UX reasons — an admin sees a global dashboard, a regular user sees their project. If the frontend is wrong, or if someone constructs a request manually, the backend enforces the right check regardless.

#### Backend enforcement is independent of frontend behavior

The backend does not trust the frontend to call the right URL. A non-employee calling `GET /api/jobs` without a project parameter receives a 403. A user calling `GET /api/jobs?project=2000` when they are not a member of project 2000 receives a 403. Both checks run on every request, unconditionally.

This means the frontend distinction is a UX optimization — it avoids showing non-employees a 403 page — not a replacement for server-side enforcement.

#### Implication for `GET /projects/{n}/jobs`

The existing `GET /api/projects/{n}/jobs` route is equivalent to `GET /api/jobs?project={n}`. Once `GET /api/jobs` is fully implemented with the scope-based pattern, `GET /api/projects/{n}/jobs` should be considered a candidate for removal to avoid maintaining two entry points to the same query. For now it remains, but new features should not be added to both.

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
