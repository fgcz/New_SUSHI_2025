# Types Usage Reference

| Type | File Location | Files Used | Reason |
|------|---------------|------------|--------|
| **Authentication Types** (`lib/types/auth.ts`) |
| `AuthenticationStatus` | `auth.ts` | `lib/api/auth.ts` | Return type for `getAuthenticationStatus()` |
| `AuthenticationConfig` | `auth.ts` | `lib/api/auth.ts` | Return type for `getAuthenticationConfig()` |
| `LoginResponse` | `auth.ts` | `lib/api/auth.ts` | Return type for `login()` and `register()` |
| `TokenVerifyResponse` | `auth.ts` | `lib/api/auth.ts` | Return type for `verifyToken()` |
| **Dataset Types** (`lib/types/dataset.ts`) |
| `Dataset` | `dataset.ts` | `lib/api/datasets.ts` | CRUD operations return type |
| `ProjectDataset` | `dataset.ts` | `app/projects/[projectNumber]/datasets/page.tsx`<br>`app/projects/[projectNumber]/datasets/[datasetId]/page.tsx`<br>`lib/types/project.ts`<br>`app/projects/[projectNumber]/datasets/page.test.tsx` | Display dataset lists<br>Display dataset details<br>Compose `ProjectDatasetsResponse`<br>Mock test data |
| `DatasetsResponse` | `dataset.ts` | `lib/api/datasets.ts` | Return type for `getDatasets()` |
| `DatasetResponse` | `dataset.ts` | `lib/api/datasets.ts` | Return type for `getDataset()` |
| `CreateDatasetResponse` | `dataset.ts` | `lib/api/datasets.ts` | Return type for `createDataset()` |
| **Project Types** (`lib/types/project.ts`) |
| `Project` | `project.ts` | `lib/types/project.ts` | Compose `UserProjectsResponse` |
| `UserProjectsResponse` | `project.ts` | `lib/api/projects.ts` | Return type for `getUserProjects()` |
| `ProjectDatasetsResponse` | `project.ts` | `lib/api/projects.ts`<br>`app/projects/[projectNumber]/datasets/page.tsx`<br>`app/projects/[projectNumber]/datasets/[datasetId]/page.tsx`<br>`app/projects/[projectNumber]/datasets/page.test.tsx`<br>`lib/api.test.ts` | Return type for `getProjectDatasets()`<br>React Query response typing<br>Dataset filtering source<br>Test mocking<br>Test assertions |
| **Misc Types** (`lib/types/misc.ts`) |
| `HelloResponse` | `misc.ts` | `lib/api/misc.ts` | Return type for `getHello()` |

## Domain-Based Import Patterns
```typescript
// Auth types
import { LoginResponse, AuthenticationStatus } from '@/lib/types/auth';

// Dataset types  
import { Dataset, ProjectDataset, DatasetsResponse } from '@/lib/types/dataset';

// Project types
import { Project, ProjectDatasetsResponse } from '@/lib/types/project';

// Or import from centralized index (exports all)
import { ProjectDataset, ProjectDatasetsResponse } from '@/lib/types';
```