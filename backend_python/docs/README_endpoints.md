# API Endpoints

All endpoints are prefixed with `/api`.

---

## Auth (`/auth`)

| Endpoint | Returns | Errors | Authorization |
|----------|---------|--------|---------------|
| `GET /login_options` | `{ldap_auth, authentication_skipped}` | - | None |
| `POST /login` | `{access_token, token_type, user}` + sets refresh cookie | 401 invalid credentials | None |
| `POST /refresh` | `{access_token, token_type}` | 401 invalid/expired token | RefreshTokenDep (cookie) |
| `POST /logout` | `{message}` | - | None (reads cookie if present) |
| `POST /logout-all` | `{message}` | 401 not authenticated | CurrentUserDep |
| `GET /me` | `{user_id, login, projects}` | 401 not authenticated | CurrentUserDep |

---

## Projects (`/projects`)

| Endpoint | Returns | Errors | Authorization |
|----------|---------|--------|---------------|
| `GET /` | `{projects, current_user}` | 401 | CurrentUserDep |
| `GET /{project_number}/datasets` | Paginated datasets | 401, 403 | CurrentUserDep + `require_project_access()` |
| `GET /{project_number}/jobs` | Paginated jobs | 401, 403 | CurrentUserDep + `require_project_access()` |
| `GET /{project_number}/datasets/tree` | `{tree, project_number}` | 401, 403 | CurrentUserDep + `require_project_access()` |
| `GET /rankings` | `{rankings}` (MOCK) | 401 | CurrentUserDep |
| `POST /{project_number}/datasets/import` | `{success, message, ...}` (MOCK) | 401, 403 | CurrentUserDep + `require_project_access()` |

---

## Datasets (`/datasets`)

| Endpoint | Returns | Errors | Authorization |
|----------|---------|--------|---------------|
| `GET /` | `{datasets, total_count, current_user}` | 401 | CurrentUserDep |
| `GET /{dataset_id}` | Full dataset with samples, headers, apps | 401, 403, 404 | CurrentUserDep + `service._get_authorized_dataset()` |
| `GET /{dataset_id}/tree` | `{tree}` | 401, 403, 404 | CurrentUserDep + `service._get_authorized_dataset()` |
| `GET /{dataset_id}/runnable_apps` | List of runnable apps | 401, 403, 404 | CurrentUserDep + `service._get_authorized_dataset()` |
| `GET /{dataset_id}/samples` | List of samples | 401, 403, 404 | CurrentUserDep + `service._get_authorized_dataset()` |

### Mock Endpoints (no project access check)

| Endpoint | Returns | Authorization |
|----------|---------|---------------|
| `POST /{dataset_id}/comment` | `{success, dataset_id, comment}` | CurrentUserDep |
| `PATCH /{dataset_id}/name` | `{success, dataset_id, new_name}` | CurrentUserDep |
| `GET /{dataset_id}/download` | `{success, dataset_id, download_url}` | CurrentUserDep |
| `GET /{dataset_id}/scripts-path` | `{path}` | CurrentUserDep |
| `POST /{dataset_id}/merge` | `{success, source_dataset_id, target_dataset_id}` | CurrentUserDep |
| `GET /{dataset_id}/parameters` | Parameters dict | CurrentUserDep |
| `POST /{dataset_id}/update-size` | `{success, dataset_id, size_bytes}` | CurrentUserDep |
| `PATCH /{dataset_id}/bfabric-id` | `{success, dataset_id, bfabric_id}` | CurrentUserDep |
| `POST /{dataset_id}/announce` | `{success, dataset_id, announced}` | CurrentUserDep |
| `DELETE /{dataset_id}` | `{success, dataset_id, deleted}` | CurrentUserDep |
| `GET /{dataset_id}/resubmit-data` | `{app_name, parameters}` | CurrentUserDep |

---

## Jobs (`/jobs`)

| Endpoint | Returns | Errors | Authorization |
|----------|---------|--------|---------------|
| `GET /` | Paginated jobs | 401 | CurrentUserDep |
| `GET /{job_id}` | Full job details | 401, 404 | CurrentUserDep |
| `GET /{job_id}/script` | `{script}` | 401, 404 | CurrentUserDep |
| `GET /{job_id}/logs` | `{stdout, stderr}` | 401, 404 | CurrentUserDep |
| `GET /{job_id}/script_mock` | `{script}` (MOCK) | 401 | CurrentUserDep |
| `GET /{job_id}/logs_mock` | `{stdout, stderr}` (MOCK) | 401 | CurrentUserDep |
| `POST /` | `{id, status, created_at, message}` (MOCK) | 401 | CurrentUserDep |

---

## Applications (`/applications`)

| Endpoint | Returns | Errors | Authorization |
|----------|---------|--------|---------------|
| `GET /` | `{omics_apps, retired_apps}` (MOCK) | 401 | CurrentUserDep |
| `GET /{app_name}` | Application config/form schema | 401, 404 | CurrentUserDep |
| `POST /{app_name}/validate` | Validated config | 401, 404 | CurrentUserDep |

---

## Files (`/files`)

| Endpoint | Returns | Errors | Authorization |
|----------|---------|--------|---------------|
| `GET /` | `{current_path, parent_path, total_items, items}` (MOCK) | 401, 404 | CurrentUserDep |
| `GET /download` | `{download_url, filename}` (MOCK) | 401 | CurrentUserDep |

---

## Error Codes

| Code | HTTP Status | Meaning |
|------|-------------|---------|
| 401 | Unauthorized | Missing or invalid token |
| 403 | Forbidden | Token valid but no access to resource |
| 404 | Not Found | Resource does not exist |

---

## Authorization Methods

| Method | Location | Description |
|--------|----------|-------------|
| `CurrentUserDep` | `app/api/deps.py` | Extracts user from JWT, returns 401 if invalid |
| `require_project_access()` | `app/api/deps.py` | Checks `project_number in user.projects`, raises 403 |
| `service._get_authorized_dataset()` | `app/services/dataset.py` | Fetches dataset, checks project access, raises 403/404 |
