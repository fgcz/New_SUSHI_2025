# Types Usage Reference

---

## Authentication Types (`lib/types/auth.ts`)

| Type | Purpose | Used In |
|------|---------|---------|
| `AuthenticationStatus` | Return type for `getAuthenticationStatus()` | `lib/api/auth.ts` |
| `AuthenticationConfig` | Return type for `getAuthenticationConfig()` | `lib/api/auth.ts` |
| `LoginResponse` | Return type for `login()` and `register()` | `lib/api/auth.ts` |
| `TokenVerifyResponse` | Return type for `verifyToken()` | `lib/api/auth.ts` |

## Dataset Types (`lib/types/dataset.ts`)

| Type | Purpose | Primary Usage |
|------|---------|---------------|
| `Dataset` | CRUD operations return type | `lib/api/datasets.ts` |
| `ProjectDataset` | Display dataset information in UI | **Pages:**<br>• Dataset listing<br>• Dataset details<br>• Tests |
| `DatasetsResponse` | Return type for `getDatasets()` | `lib/api/datasets.ts` |
| `DatasetResponse` | Return type for `getDataset()` | `lib/api/datasets.ts` |
| `CreateDatasetResponse` | Return type for `createDataset()` | `lib/api/datasets.ts` |
| `DatasetRunnableApp` | Runnable applications structure | **Components:**<br>• Dataset detail page<br>• Mock API responses |
| `DatasetTreeNode` | Folder tree structure | **Components:**<br>• TreeComponent<br>• Mock API responses |
| `DatasetSample` | Sample data structure | **Components:**<br>• Dataset detail page<br>• Mock API responses |

---

## Project Types (`lib/types/project.ts`)

| Type | Purpose | Primary Usage |
|------|---------|---------------|
| `Project` | Compose `UserProjectsResponse` | `lib/types/project.ts` |
| `UserProjectsResponse` | Return type for `getUserProjects()` | `lib/api/projects.ts` |
| `ProjectDatasetsResponse` | Return type for `getProjectDatasets()` | **Widespread:**<br>• API layer<br>• React Query<br>• All dataset pages<br>• Tests |

## Job Types (`lib/types/job.ts`)

| Type | Purpose | Primary Usage |
|------|---------|---------------|
| `JobSubmissionRequest` | Job submission payload structure (uses DynamicFormData) | **Components:**<br>• Run-application page<br>• Job API |
| `JobSubmissionResponse` | Job submission response structure | `lib/api/jobs.ts` |
| `DynamicFormData` | Dynamic form state management | **Components:**<br>• Form renderer utility<br>• Run-application page<br>• JobSubmissionRequest parameters |

## App Form Types (`lib/types/app-form.ts`)

| Type | Purpose | Primary Usage |
|------|---------|---------------|
| `AppFormField` | Dynamic form field definition | **Components:**<br>• Applications API<br>• Form renderer |
| `AppFormResponse` | API response structure (includes app description) | **Components:**<br>• Applications API<br>• Run-application page |

## Misc Types (`lib/types/misc.ts`)

| Type | Purpose | Used In |
|------|---------|---------|
| `HelloResponse` | Return type for `getHello()` | `lib/api/misc.ts` |

## Domain-Based Import Patterns
```typescript
// Dataset types  
import { Dataset, ProjectDataset, DatasetRunnableApp, DatasetTreeNode } from '@/lib/types/dataset';

// Job submission types
import { JobSubmissionRequest, DynamicFormData } from '@/lib/types/job';

// Or import from centralized index (exports all)
import { ProjectDataset, ProjectDatasetsResponse, AppFormField, JobSubmissionRequest } from '@/lib/types';
```

## File Structure Overview
```
lib/types/
├── index.ts              # Centralized exports
├── auth.ts               # Authentication & user management
├── app-form.ts           # Dynamic form definitions
├── dataset.ts            # Dataset, samples, tree nodes, runnable apps
├── project.ts            # Project-level operations
├── job.ts                # Job submission (static & dynamic)
└── misc.ts               # Utility/misc types
```

