# API Documentation

**Last Updated:** 2026-01-29

---

## Quick Resume

| Route | Used In | Function | Status |
|-------|---------|----------|--------|
| `GET /api/v1/projects` | `/projects` | `projectApi.getUserProjects()` | ✅ Real |
| `GET /api/v1/projects/{id}/datasets` | `/projects/{id}/datasets` | `projectApi.getProjectDatasets()` | ✅ Real |
| `GET /api/v1/projects/{id}/datasets/tree` | `/projects/{id}/datasets` | `projectApi.getProjectDatasetsTree()` | ✅ Real |
| `GET /api/v1/projects/{id}/jobs` | `/projects/{id}/jobs` | `projectApi.getProjectJobs()` | ✅ Real |
| `(TODO) POST /api/v1/projects/{id}/datasets/import` | `/projects/{id}/datasets/import` | `projectApi.importDataset()` | 🔶 Mock |
| `(TODO) GET /api/v1/projects/{id}/datasets/download` | `/projects/{id}/datasets` | `projectApi.getDownloadAllDatasets()` | 🔶 Mock |
| `(TODO) GET /api/v1/projects/{id}/rankings` | `/projects/{id}` | `projectApi.getRankings()` | 🔶 Mock |
| `(TODO) GET /api/v1/datasets/{datasetId}/project` | Header search | `projectApi.validateDatasetId()` | 🔶 Mock |
| `(TODO) GET /api/v1/jobs/{jobId}/project` | `/jobs/{id}/script` | `projectApi.getProjectIdFromJob()` | 🔶 Mock |
||||
| `GET /api/v1/datasets/{id}` | `/projects/{id}/datasets/{id}` | `datasetApi.getDataset()` | ⚠️ Real + Mock injection |
| `GET /api/v1/datasets/{id}/tree` | `/projects/{id}/datasets/{id}` | `datasetApi.getDatasetTree()` | ✅ Real |
| `(TODO) POST /api/v1/datasets/{id}/comment` | `/projects/{id}/datasets/{id}` | `datasetApi.addComment()` | 🔶 Mock |
| `(TODO) PATCH /api/v1/datasets/{id}/rename` | `/projects/{id}/datasets/{id}` | `datasetApi.renameDataset()` | 🔶 Mock |
| `(TODO) GET /api/v1/datasets/{id}/download` | `/projects/{id}/datasets/{id}` | `datasetApi.downloadDataset()` | 🔶 Mock |
| `(TODO) GET /api/v1/datasets/{id}/scripts-path` | `/projects/{id}/datasets/{id}` | `datasetApi.getScriptsPath()` | 🔶 Mock |
| `(TODO) GET /api/v1/datasets/{id}/data-folder` | `/projects/{id}/datasets/{id}` | `datasetApi.getDatasetDataFolder()` | 🔶 Mock |
| `(TODO) POST /api/v1/datasets/{id}/merge` | `/projects/{id}/datasets/{id}` | `datasetApi.mergeDataset()` | 🔶 Mock |
| `(TODO) GET /api/v1/datasets/{id}/parameters` | `/projects/{id}/datasets/{id}/parameters` | `datasetApi.getDatasetParameters()` | 🔶 Mock |
| `(TODO) POST /api/v1/datasets/{id}/update-size` | `/projects/{id}/datasets/{id}` | `datasetApi.updateSize()` | 🔶 Mock |
| `(TODO) PATCH /api/v1/datasets/{id}/bfabric-id` | `/projects/{id}/datasets/{id}` | `datasetApi.setBFabricId()` | 🔶 Mock |
| `(TODO) POST /api/v1/datasets/{id}/announce` | `/projects/{id}/datasets/{id}` | `datasetApi.announceDataset()` | 🔶 Mock |
| `(TODO) POST /api/v1/datasets/{id}/geo-upload` | `/projects/{id}/datasets/{id}` | `datasetApi.geoUploader()` | 🔶 Mock |
| `(TODO) DELETE /api/v1/datasets/{id}` | `/projects/{id}/datasets/{id}` | `datasetApi.deleteDataset()` | 🔶 Mock |
| `(TODO) GET /api/v1/datasets/{id}/resubmit-data` | `/projects/{id}/datasets/{id}/run-application/{app}` | `datasetApi.getResubmitData()` | 🔶 Mock |
||||
| `(TODO) POST /api/v1/jobs` | `/projects/{id}/datasets/{id}/run-application/{app}/confirm` | `jobApi.submitJob()` | 🔶 Mock |
| `(TODO) GET /api/v1/jobs/{id}` | `/jobs/{id}/logs`, `/jobs/{id}/script` | `jobApi.getJob()` | 🔶 Mock |
| `GET /api/v1/jobs` | - | `jobApi.getAllJobs()` | ✅ Real (unused) |
| `(TODO) GET /api/v1/jobs/{id}/script` | `/jobs/{id}/script` | `jobApi.getJobScript()` | 🔶 Mock |
| `(TODO) GET /api/v1/jobs/{id}/logs` | `/jobs/{id}/logs` | `jobApi.getJobLogs()` | 🔶 Mock |
||||
| `GET /api/v1/application_configs/{appName}` | `/projects/{id}/datasets/{id}/run-application/{app}` | `applicationApi.getFormSchema()` | ⚠️ Real + Mock for CountQC |
| `(TODO) POST /api/v1/application_configs/{appName}/validate` | `/projects/{id}/datasets/{id}/run-application/{app}` | `applicationApi.validateAppConfig()` | 🔶 Mock |
||||
| `(TODO) GET /api/v1/files/{path}` | `/files/{path}` | `filesApi.getDirectoryContents()` | 🔶 Mock |
| `(TODO) GET /api/v1/files/{path}/download` | `/files/{path}` | `filesApi.getDownloadUrl()` | 🔶 Mock |
||||
| `POST /api/v1/auth/login` | `/login` | `authApi.login()` | ✅ Real |
| `POST /api/v1/auth/register` | `/login` | `authApi.register()` | ✅ Real |
| `GET /api/v1/auth/verify` | AuthContext | `authApi.verifyToken()` | ✅ Real |
| `GET /auth/login_options` | AuthContext | `authApi.getAuthenticationStatus()` | ✅ Real |
| `GET /api/v1/authentication_config` | AuthContext | `authApi.getAuthenticationConfig()` | ✅ Real |
| (client-only) | `/logout` | `authApi.logout()` | ✅ Real |

**Legend:** ✅ Real API call | 🔶 Mock (TODO backend) | ⚠️ Real with modifications

---

## Project APIs

### ProjectApi (`lib/api/projects.ts`)

| Function | Route | Params | Returns | Status |
|----------|-------|--------|---------|--------|
| `getUserProjects()` | `GET /api/v1/projects` | - | `UserProjectsResponse` | ✅ Real |
| `getProjectDatasets()` | `GET /api/v1/projects/{id}/datasets` | `{ q?, user?, page?, per? }` | `DatasetListResponse` | ✅ Real |
| `getProjectJobs()` | `GET /api/v1/projects/{id}/jobs` | `{ status?, user?, dataset_id?, from_date?, to_date?, page?, per? }` | `JobListResponse` | ✅ Real |
| `getProjectDatasetsTree()` | `GET /api/v1/projects/{id}/datasets/tree` | - | `{ tree: DatasetTreeResponse }` | ✅ Real |
| `getDownloadAllDatasets()` | `GET /api/v1/projects/{id}/datasets/download` | - | `{ id: number }` | 🔶 Mock |
| `validateDatasetId()` | `GET /api/v1/datasets/{id}/project` | `user, datasetId` | `{ projectId: number }` | 🔶 Mock |
| `getRankings()` | `GET /api/v1/projects/{id}/rankings` | - | `{ rankings: Array<...> }` | 🔶 Mock |
| `importDataset()` | `POST /api/v1/projects/{id}/datasets/import` | `{ file, name, parentId }` | `void` | 🔶 Mock |
| `getProjectIdFromJob()` | `GET /api/v1/jobs/{id}/project` | `jobId` | `{ projectId: number }` | 🔶 Mock |

**Return Types:**
- `UserProjectsResponse`: `{ projects: Array<{ number }>, current_user }`
- `DatasetListResponse`: `{ datasets: DatasetMinimal[], total_count, page, per, project_number }`
- `JobListResponse`: `{ jobs: JobMinimal[], total_count, page, per, project_number, filters: object }`
- `DatasetTreeResponse`: `Array<{ id, text, parent: string|number, a_attr: object, dataset_data: DatasetMinimal }>`

---

## Dataset APIs

### DatasetApi (`lib/api/datasets.ts`)

| Function | Route | Params | Returns | Status |
|----------|-------|--------|---------|--------|
| `getDataset()` | `GET /api/v1/datasets/{id}` | `id` | `DatasetFullResponse` | ⚠️ Real + injects mock CountQC app |
| `getDatasetTree()` | `GET /api/v1/datasets/{id}/tree` | `id` | `DatasetTreeResponse` | ✅ Real |
| `addComment()` | `POST /api/v1/datasets/{id}/comment` | `datasetId, comment` | `void` | 🔶 Mock |
| `renameDataset()` | `PATCH /api/v1/datasets/{id}/rename` | `datasetId, newName` | `void` | 🔶 Mock |
| `downloadDataset()` | `GET /api/v1/datasets/{id}/download` | `datasetId` | `void` | 🔶 Mock |
| `getScriptsPath()` | `GET /api/v1/datasets/{id}/scripts-path` | `datasetId` | `{ path: string }` | 🔶 Mock |
| `getDatasetDataFolder()` | `GET /api/v1/datasets/{id}/data-folder` | `datasetId` | `{ path: string }` | 🔶 Mock |
| `mergeDataset()` | `POST /api/v1/datasets/{id}/merge` | `datasetId` | `void` | 🔶 Mock |
| `getDatasetParameters()` | `GET /api/v1/datasets/{id}/parameters` | `datasetId` | `Record<string, string>` | 🔶 Mock |
| `updateSize()` | `POST /api/v1/datasets/{id}/update-size` | `datasetId` | `void` | 🔶 Mock |
| `setBFabricId()` | `PATCH /api/v1/datasets/{id}/bfabric-id` | `datasetId, bfabricId` | `void` | 🔶 Mock |
| `announceDataset()` | `POST /api/v1/datasets/{id}/announce` | `datasetId` | `void` | 🔶 Mock |
| `geoUploader()` | `POST /api/v1/datasets/{id}/geo-upload` | `datasetId` | `void` | 🔶 Mock |
| `deleteDataset()` | `DELETE /api/v1/datasets/{id}` | `datasetId` | `void` | 🔶 Mock |
| `getResubmitData()` | `GET /api/v1/datasets/{id}/resubmit-data` | `datasetId` | `{ appName, parameters }` | 🔶 Mock |

**Return Types:**
- `DatasetFullResponse`: `{ id, name, sushi_app_name, completed_samples, samples_length, parent_id?, children_ids: number[], user_login, created_at, bfabric_id?, project_number, comment?, applications: DatasetAppCategory[] }`

---

## Job APIs

### JobApi (`lib/api/jobs.ts`)

| Function | Route | Params | Returns | Status |
|----------|-------|--------|---------|--------|
| `submitJob()` | `POST /api/v1/jobs` | `JobSubmissionRequest` | `JobSubmissionResponse` | 🔶 Mock (2s delay) |
| `getJob()` | `GET /api/v1/jobs/{id}` | `jobId` | `JobFullResponse` | 🔶 Mock (2s delay) |
| `getAllJobs()` | `GET /api/v1/jobs` | `{ datasetName?, user?, page?, per? }` | `JobListResponse` | ✅ Real (unused) |
| `getJobScript()` | `GET /api/v1/jobs/{id}/script` | `jobId` | `string` | 🔶 Mock (hardcoded Python script) |
| `getJobLogs()` | `GET /api/v1/jobs/{id}/logs` | `jobId` | `string` | 🔶 Mock (hardcoded logs) |

**Return Types:**
- `JobSubmissionRequest`: `{ dataset_id, application_name, parameters: DynamicFormData }`
- `JobSubmissionResponse`: `{ id, status, created_at: string, message }`
- `JobFullResponse`: `{ id, status, user, input_dataset_id, next_dataset_id, created_at, script_path, submit_job_id, start_time, end_time?, updated_at }`

---

## Application APIs

### ApplicationApi (`lib/api/applications.ts`)

| Function | Route | Params | Returns | Status |
|----------|-------|--------|---------|--------|
| `getFormSchema()` | `GET /api/v1/application_configs/{appName}` | `appName` | `AppFormResponse` | ⚠️ Real, mocked for "CountQC" |
| `validateAppConfig()` | `POST /api/v1/application_configs/{appName}/validate` | `appName, currentConfig` | `AppFormResponse` | 🔶 Mock |

**Return Types:**
- `AppFormResponse`: `{ application: { name, class_name, category, description, required_columns, required_params, modules, form_fields: AppFormField[] } }`
- `AppFormField`: `{ name, type, default_value?, description?, options?, disabled? }`

---

## Files APIs

### FilesApi (`lib/api/files.ts`)

| Function | Route | Params | Returns | Status |
|----------|-------|--------|---------|--------|
| `getDirectoryContents()` | `GET /api/v1/files/{path}` | `path` | `DirectoryContents` | 🔶 Mock (hardcoded file tree) |
| `getDownloadUrl()` | `GET /api/v1/files/{path}/download` | `path` | `string` | 🔶 Mock |

**Return Types:**
- `DirectoryContents`: `{ currentPath, parentPath, totalItems, items: FileItem[] }`
- `FileItem`: `{ name, type: 'file' | 'folder', lastModified, size: number | null }`

---

## Authentication APIs

### AuthApi (`lib/api/auth.ts`)

| Function | Route | Params | Returns | Status |
|----------|-------|--------|---------|--------|
| `login()` | `POST /api/v1/auth/login` | `login, password` | `LoginResponse` | ✅ Real |
| `register()` | `POST /api/v1/auth/register` | `login, email, password, password_confirmation` | `LoginResponse` | ✅ Real |
| `logout()` | (client-only) | - | `void` | ✅ Real |
| `verifyToken()` | `GET /api/v1/auth/verify` | - | `TokenVerifyResponse` | ✅ Real |
| `getAuthenticationStatus()` | `GET /auth/login_options` | - | `AuthenticationStatus` | ✅ Real |
| `getAuthenticationConfig()` | `GET /api/v1/authentication_config` | - | `AuthenticationConfig` | ✅ Real |

**Return Types:**
- `LoginResponse`: `{ token, user: User }`
- `TokenVerifyResponse`: `{ valid, user?: User }`
- `AuthenticationStatus`: `{ authentication_skipped, current_user? }`
- `AuthenticationConfig`: `{ methods: string[], ldap_enabled }`

---

## API Usage by Page

| Page | APIs Used |
|------|-----------|
| `/login` | `authApi.login()`, `authApi.register()` |
| `/logout` | `authApi.logout()` |
| `/projects` | `projectApi.getUserProjects()` |
| `/projects/[id]` | `projectApi.getRankings()` |
| `/projects/[id]/datasets` | `projectApi.getProjectDatasets()`, `projectApi.getProjectDatasetsTree()`, `projectApi.getDownloadAllDatasets()` |
| `/projects/[id]/datasets/import` | `projectApi.importDataset()` |
| `/projects/[id]/datasets/[datasetId]` | `datasetApi.getDataset()`, `datasetApi.*` (action buttons) |
| `/projects/[id]/datasets/[datasetId]/parameters` | `datasetApi.getDatasetParameters()` |
| `/projects/[id]/datasets/[datasetId]/run-application/[app]` | `applicationApi.getFormSchema()`, `applicationApi.validateAppConfig()`, `datasetApi.getResubmitData()` |
| `/projects/[id]/datasets/[datasetId]/run-application/[app]/confirm` | `jobApi.submitJob()` |
| `/projects/[id]/jobs` | `projectApi.getProjectJobs()` |
| `/jobs/[jobId]/script` | `jobApi.getJobScript()`, `projectApi.getProjectIdFromJob()` |
| `/jobs/[jobId]/logs` | `jobApi.getJobLogs()`, `projectApi.getProjectIdFromJob()` |
| `/files/[...path]` | `filesApi.getDirectoryContents()`, `filesApi.getDownloadUrl()` |
| AuthContext | `authApi.getAuthenticationStatus()`, `authApi.verifyToken()`, `authApi.logout()` |
| Header | `projectApi.validateDatasetId()` |

---

## Naming Conventions

All API functions follow these patterns:
- `get*()` - Fetch data (GET requests)
- `set*()` - Update single field (PATCH requests)
- `add*()` - Add new item (POST requests)
- `update*()` - Update resource (PUT/POST requests)
- `delete*()` - Remove resource (DELETE requests)

---

## Notes

### Mock Behavior
- Mock functions return `Promise.resolve()` for void operations
- Mock functions with delays simulate network latency (e.g., `submitJob` has 2s delay)

### Hardcoded Values in Mocks
- `projectId: 1001` - Used in `validateDatasetId()`, `getProjectIdFromJob()`
- File paths like `p1001/whatever_path_we_get` in `getScriptsPath()`
- Rankings data with 10 hardcoded users

### Backend Parameter Mapping
- Frontend uses `q` for dataset name search
- Job filters: `status`, `user`, `dataset_id`, `from_date`, `to_date`, `page`, `per`
- Dataset filters: `q` (name search), `user`, `page`, `per`
