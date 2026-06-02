# Frontend Architecture
**Last Updated:** 2026-03-19

This document describes the folder structure, technology stack, and architectural decisions for the MultiOmicsStudio frontend application.

## Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| Framework | Next.js 14 (App Router) | Server-side rendering, routing, API routes |
| Language | TypeScript 5 | Type safety |
| Styling | Tailwind CSS 3 | Utility-first CSS |
| Server State | TanStack Query (React Query) | Data fetching, caching, synchronization |
| Testing | Vitest + Testing Library + MSW | Unit/integration tests with API mocking |
| Data Grid | Handsontable | Excel-like sample editing |

## Folder Structure

```
frontend/
├── app/                          # Next.js App Router pages
│   ├── layout.tsx                # Root layout with providers
│   ├── page.tsx                  # Home page (redirects to /projects)
│   ├── Header.tsx                # Global navigation header
│   │
│   ├── login/                    # Authentication pages
│   ├── logout/
│   │
│   ├── projects/                 # Project-scoped pages
│   │   ├── page.tsx              # Project list
│   │   └── [projectNumber]/
│   │       ├── page.tsx          # Project dashboard
│   │       ├── datasets/         # Dataset management
│   │       │   ├── page.tsx      # Dataset list (table/tree view)
│   │       │   ├── import/       # Import new dataset
│   │       │   └── [datasetId]/
│   │       │       ├── page.tsx  # Dataset detail
│   │       │       ├── samples/edit/     # Edit samples (Handsontable)
│   │       │       ├── factors/edit/     # Edit factors (Handsontable)
│   │       │       ├── parameters/       # View parameters
│   │       │       ├── jobs/             # Dataset-specific jobs
│   │       │       └── run-application/  # Run omics applications
│   │       │           └── [appName]/
│   │       │               ├── page.tsx  # Dynamic form
│   │       │               └── confirm/  # Submission confirmation
│   │       └── jobs/             # Project jobs list
│   │
│   ├── jobs/                     # Job detail pages (project-agnostic URLs)
│   │   └── [jobid]/
│   │       ├── script/           # View job script
│   │       └── logs/             # View job logs
│   │
│   ├── dataset/                  # Global dataset pages
│   │   └── list/                 # Global dataset search
│   │
│   ├── files/                    # File browser
│   │   └── [...path]/            # Dynamic path segments
│   │
│   └── help/                     # Help page
│
├── lib/                          # Shared library code
│   ├── api/                      # API client modules
│   │   ├── client.ts             # HTTP client (fetch wrapper)
│   │   ├── index.ts              # Re-exports
│   │   ├── projects.ts           # Project & dataset list APIs
│   │   ├── datasets.ts           # Individual dataset APIs
│   │   ├── jobs.ts               # Job APIs
│   │   ├── applications.ts       # Application form schema APIs
│   │   ├── files.ts              # File browser APIs
│   │   └── auth.ts               # Authentication APIs
│   │
│   ├── hooks/                    # Custom React hooks
│   │   ├── index.ts              # Re-exports all hooks
│   │   ├── shared/               # Reusable UI hooks
│   │   │   ├── useSearch.ts      # URL-synced search input
│   │   │   └── usePagination.ts  # URL-synced pagination
│   │   ├── project/              # Project data hooks
│   │   │   ├── useProjectList.ts
│   │   │   ├── useProjectDatasets.ts
│   │   │   └── useProjectJobs.ts
│   │   ├── dataset/              # Dataset data hooks
│   │   │   ├── useDatasetBase.ts
│   │   │   ├── useDatasetTree.ts
│   │   │   └── useImportDatasetForm.ts
│   │   ├── job/                  # Job data hooks
│   │   │   └── useJobsFilters.ts
│   │   └── application/          # Application form hooks
│   │       ├── useApplicationFormSchema.ts
│   │       ├── useApplicationForm.ts
│   │       └── useJobSubmission.ts
│   │
│   ├── types/                    # TypeScript type definitions
│   │   ├── index.ts              # Re-exports
│   │   ├── dataset.ts            # Dataset types
│   │   ├── job.ts                # Job types
│   │   ├── app-form.ts           # Dynamic form types
│   │   └── auth.ts               # Auth types
│   │
│   ├── utils/                    # Utility functions
│   │   └── form-renderer.tsx     # Dynamic form field components
│   │
│   └── ui/                       # Shared UI components (if any)
│
├── providers/                    # React Context providers
│   ├── AuthContext.tsx           # Authentication state
│   └── QueryProvider.tsx         # TanStack Query client
│
├── mocks/                        # MSW test mocks
│   ├── handlers.ts               # API mock handlers
│   ├── server.ts                 # Test server setup
│   ├── test-utils.tsx            # Test helpers (renderWithQuery)
│   └── data/                     # Mock response data
│
├── docs/                         # Developer documentation
│
└── config/                       # Configuration files
```

## Data Flow

### 1. Server State (API Data)

```
User Action → Hook (useQuery) → API Client → Backend
                  ↓
              Cache (TanStack Query)
                  ↓
              Component renders with data
```

All API data flows through TanStack Query hooks, which handle:
- Automatic caching (default 60s stale time)
- Background refetching
- Loading/error states
- Data synchronization

### 2. URL State (Pagination, Search, Filters)

```
User types in input → Local state (immediate feedback)
                          ↓
                    Debounce (300ms)
                          ↓
                    URL updates (?page=2&q=search)
                          ↓
                    Hook reads URL → useQuery refetches
```

URL-driven state enables:
- Shareable links
- Browser back/forward navigation
- Bookmarkable searches

### 3. Form State (Job Submission)

```
User fills form → Component state
                      ↓
                  localStorage (persist across pages)
                      ↓
                  Confirmation page reads localStorage
                      ↓
                  Submit to API → Clear localStorage
```

## Key Patterns

### Page Structure

Each page typically follows this pattern:

```tsx
export default function SomePage() {
  // 1. URL params
  const params = useParams();

  // 2. URL-driven state (pagination, search)
  const { page, per } = usePagination();
  const { searchQuery } = useSearch('q');

  // 3. Data fetching
  const { data, isLoading, error } = useQuery({...});

  // 4. Loading state
  if (isLoading) return <PageSkeleton />;

  // 5. Error state
  if (error) return <ErrorDisplay />;

  // 6. Main render
  return <div>...</div>;
}
```

### API Client Pattern

```tsx
// lib/api/something.ts
export const somethingApi = {
  async getSomething(id: number): Promise<SomethingResponse> {
    return httpClient.request<SomethingResponse>(`/api/v1/something/${id}`);
  },

  async createSomething(data: CreateRequest): Promise<void> {
    return httpClient.request('/api/v1/something', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  },
};
```

### Hook Pattern

```tsx
// lib/hooks/something/useSomething.ts
export function useSomething(id: number) {
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['something', id],
    queryFn: () => somethingApi.getSomething(id),
    staleTime: 60_000,
  });

  return {
    something: data,
    isLoading,
    error,
    isEmpty: !isLoading && !data,
    refetch,
  };
}
```


## Provider Hierarchy

```tsx
// app/layout.tsx
<QueryProvider>           // TanStack Query client
  <AuthProvider>          // Authentication context
    <Header />            // Global navigation
    {children}            // Page content
  </AuthProvider>
</QueryProvider>
```

## Related Documentation

- [Hooks Documentation](./hooks.md) - Detailed hook API reference
- [API Documentation](./backendCalls.md) - Backend API endpoints
- [Types Documentation](./types.md) - TypeScript type definitions
- [Pagination](./pagination.md) - URL-driven pagination system
- [Testing](./tests.md) - Testing patterns and setup
