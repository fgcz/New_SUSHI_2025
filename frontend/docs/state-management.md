# State Management and Data Persistence
**Last Updated:** 2026-03-19

This document explains how we handle different types of state in the Sushi frontend application.

## Overview

We use different strategies for different types of state:

| State Type | Solution | Persistence | Use Case |
|------------|----------|-------------|----------|
| Server State | TanStack Query | Cached (60s) | API data (datasets, jobs, etc.) |
| URL State | URL Parameters | Browser history | Pagination, search, filters |
| Form State | localStorage | Until cleared | Multi-page form wizards |
| Component State | useState | None | Local UI state |

## 1. Server State (TanStack Query)

All data fetched from the backend is managed by TanStack Query (React Query).

### Why TanStack Query?

- **Automatic caching** - Reduces redundant API calls
- **Background refetching** - Keeps data fresh
- **Loading/error states** - Built-in state management
- **Optimistic updates** - Instant UI feedback
- **Request deduplication** - Multiple components can use same data

### Configuration

```tsx
// providers/QueryProvider.tsx
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60_000,        // Data stays fresh for 1 minute
      refetchOnWindowFocus: false,
    },
  },
});
```

### Usage Pattern

```tsx
// In a component
const { data, isLoading, error } = useQuery({
  queryKey: ['datasets', projectNumber, { page, per, q: searchQuery }],
  queryFn: () => projectApi.getProjectDatasets(projectNumber, { page, per, q: searchQuery }),
  placeholderData: keepPreviousData,  // Show old data while fetching new
});
```

### Cache Keys

Cache keys should include all parameters that affect the data:

```tsx
// Good - includes all relevant params
queryKey: ['datasets', projectNumber, { page, per, q: searchQuery }]

// Bad - missing params, will show stale data
queryKey: ['datasets', projectNumber]
```

## 2. URL State (Pagination, Search, Filters)

UI state that should be shareable and bookmarkable is stored in URL parameters.

### Benefits

- **Shareable links** - Copy URL to share exact view
- **Browser history** - Back/forward buttons work correctly
- **Refresh resilient** - State survives page refresh
- **SEO friendly** - Search engines can index different states

### Implementation

We use custom hooks that sync with URL:

```tsx
// usePagination - manages ?page= and ?per=
const { page, per, goToPage, changePerPage } = usePagination(10);

// useSearch - manages any search param with debounce
const { searchQuery, localQuery, setLocalQuery } = useSearch('q', 300);

// useJobsFilters - manages multiple filter params
const { filters, localFilters, setStatusLocal, clearFilters } = useJobsFilters();
```

### Two-Value Pattern

URL state hooks return two versions of each value:

```tsx
const { localQuery, searchQuery } = useSearch('q');

// localQuery - Updates immediately when user types
//            - Use for input field value (instant feedback)

// searchQuery - Updates after debounce, synced to URL
//             - Use for API calls (stable value)
```

### Data Flow

```
User types → localQuery updates → UI shows input immediately
                ↓
           300ms debounce
                ↓
         URL updates (?q=value)
                ↓
         searchQuery updates
                ↓
         useQuery refetches with new params
```

## 3. Form State (localStorage)

For multi-page form wizards (like job submission), we use localStorage to persist data between pages.

### Why localStorage?

- **Large data support** - Can hold 5-10MB (browser dependent)
- **Survives refresh** - Data persists across page reloads
- **Survives navigation** - Data available on destination page
- **Simple API** - No external dependencies

### Implementation

```tsx
// Source page - save data before navigation
const handleContinue = () => {
  localStorage.setItem('jobSubmissionData', JSON.stringify({
    datasetId,
    appName,
    nextDataset: nextDatasetData,
    parameters: formValues,
  }));
  router.push(`/projects/${projectNumber}/datasets/${datasetId}/run-application/${appName}/confirm`);
};

// Destination page - retrieve and validate data
useEffect(() => {
  const stored = localStorage.getItem('jobSubmissionData');
  if (!stored) {
    setError('No job data found. Please start from the application form.');
    return;
  }

  const data = JSON.parse(stored);

  // Validate data matches current URL
  if (data.datasetId !== Number(datasetId) || data.appName !== appName) {
    setError('Job data does not match current page.');
    return;
  }

  setJobData(data);
}, [datasetId, appName]);

// After successful submission - clear data
const handleSubmit = async () => {
  await jobApi.submitJob(jobData);
  localStorage.removeItem('jobSubmissionData');
  router.push('/success');
};
```

### Important: Always Clear Data

localStorage persists until explicitly cleared. Always remove data after:
- Successful form submission
- User cancellation
- Navigation away from workflow

```tsx
// Clear on unmount if user abandons flow
useEffect(() => {
  return () => {
    // Optional: clear if navigating away
    // localStorage.removeItem('jobSubmissionData');
  };
}, []);
```

### Validation Pattern

Always validate localStorage data against current page context:

```tsx
const stored = JSON.parse(localStorage.getItem('formData') || '{}');

// Check required fields exist
if (!stored.datasetId || !stored.appName) {
  return <Error message="Missing required data" />;
}

// Check data matches URL params
if (stored.datasetId !== currentDatasetId) {
  return <Error message="Data mismatch - please restart" />;
}
```

## 4. Component State (useState)

For purely local UI state that doesn't need persistence:

### Use Cases

- Modal open/close
- Dropdown expanded state
- Form field values (before submission)
- Selection state (checkboxes)
- Hover/focus states

### Example

```tsx
function DatasetTable({ datasets }) {
  // Local selection state - no need to persist
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());

  // Local modal state
  const [isDeleteModalOpen, setDeleteModalOpen] = useState(false);

  const toggleSelect = (id: number) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  return (
    <>
      <table>
        {datasets.map(ds => (
          <tr key={ds.id}>
            <td>
              <input
                type="checkbox"
                checked={selectedIds.has(ds.id)}
                onChange={() => toggleSelect(ds.id)}
              />
            </td>
            ...
          </tr>
        ))}
      </table>

      <DeleteModal
        isOpen={isDeleteModalOpen}
        onClose={() => setDeleteModalOpen(false)}
        selectedIds={selectedIds}
      />
    </>
  );
}
```

## Alternative: React Context

React Context can be used for app-wide state shared across components, but has limitations:

### When to Use Context

- Theme preferences
- User settings
- Authentication state (we use AuthContext)

### When NOT to Use Context

- Multi-page form data (lost on refresh)
- Large data sets (causes re-renders)
- Frequently changing data

### Our AuthContext Example

```tsx
// providers/AuthContext.tsx
const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [authStatus, setAuthStatus] = useState<AuthenticationStatus | null>(null);
  const [loading, setLoading] = useState(true);

  // Check auth on mount
  useEffect(() => {
    checkAuth();
  }, []);

  return (
    <AuthContext.Provider value={{ authStatus, loading, logout, refetch }}>
      {children}
    </AuthContext.Provider>
  );
}

// Usage in any component
const { authStatus, logout } = useAuth();
```

## Decision Tree

When deciding where to store state:

```
Is it from an API?
  └─ Yes → TanStack Query

Should it be in the URL (shareable/bookmarkable)?
  └─ Yes → URL parameters (useSearch, usePagination)

Does it need to persist across page navigation?
  └─ Yes → localStorage

Is it shared across many components?
  └─ Yes → React Context (rare)

Otherwise → useState (local component state)
```

## Related Documentation

- [Pagination](./pagination.md) - Detailed URL state implementation
- [Hooks](./hooks.md) - Hook API reference
- [Providers](./providers.md) - Context provider details
