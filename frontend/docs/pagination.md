# Pagination and Search Architecture

This document explains how our pagination and search system works, focusing on the separation of concerns between URL state management and data fetching.

## Architecture Overview

Our pagination system consists of two main layers:

1. **URL State Management**: Hooks that synchronize form inputs with URL parameters
2. **Data Fetching**: Hooks that automatically refetch data when URL parameters change

## Point 1: URL State Synchronization

The `useSearch` and `usePagination` hooks have a **single responsibility**: synchronizing user input with URL parameters.

### useSearch Hook

```tsx
const { searchQuery, localQuery, setLocalQuery, onSubmit } = useSearch();
```

**What it does:**
- Reads `q` parameter from URL → `searchQuery`
- Maintains local input state → `localQuery` (for immediate UI feedback)
- Debounces input changes (300ms) before updating URL
- Synchronizes browser navigation (back/forward buttons)

**What it does NOT do:**
- Does not fetch data
- Does not know about datasets, jobs, or any business logic
- Only manages the `q` URL parameter

### usePagination Hook

```tsx
const { page, per, goToPage, changePerPage } = usePagination(defaultPerPage);
```

**What it does:**
- Reads `page` and `per` parameters from URL
- Provides functions to update these URL parameters
- Resets to page 1 when changing per-page count

**What it does NOT do:**
- Does not fetch data
- Does not calculate total pages or items
- Only manages `page` and `per` URL parameters

### Key Point: Pure URL Management

```tsx
// These hooks only produce 3 values from URL:
const searchQuery = searchParams.get('q') || '';           // From useSearch
const page = Number(searchParams.get('page') || 1);        // From usePagination  
const per = Number(searchParams.get('per') || 50);         // From usePagination

// They don't know what data will be fetched with these parameters
```

## Point 2: Automatic Data Refetching

The `useProjectDatasets` hook automatically refetches data when the 3 URL-derived values change.

### useProjectDatasets Hook

```tsx
const { datasets, total, isLoading } = useProjectDatasets({
  projectNumber,
  q: searchQuery,    // ← From useSearch hook
  page,              // ← From usePagination hook  
  per                // ← From usePagination hook
});
```

**How it works:**
- Uses TanStack Query with a cache key: `['datasets', projectNumber, { q, page, per }]`
- When any of `q`, `page`, or `per` change, the cache key changes
- TanStack Query automatically triggers a new API call for the new cache key
- Previous data is shown while loading (via `placeholderData: keepPreviousData`)

### Data Flow Example

```
User types "test" in search input
↓
useSearch: localQuery = "test" (immediate UI update)
↓  
After 300ms debounce: URL updates to ?q=test&page=1
↓
useSearch: searchQuery = "test" (derived from new URL)
↓
useProjectDatasets: receives new searchQuery
↓
TanStack Query: cache key changes, triggers API call
↓
API: GET /api/v1/projects/1001/datasets?q=test&page=1&per=50
↓
Component: re-renders with filtered datasets
```

## Complete Flow in Code

```tsx
function ProjectDatasetsPage() {
  // Step 1: Get URL-derived values
  const { searchQuery, localQuery, setLocalQuery, onSubmit } = useSearch();
  const { page, per, goToPage, changePerPage } = usePagination();
  
  // Step 2: Pass values to data fetching hook
  const { datasets, total, totalPages, isLoading } = useProjectDatasets({
    projectNumber,
    q: searchQuery,    // ← URL-derived
    page,              // ← URL-derived  
    per                // ← URL-derived
  });
  
  // Step 3: Render UI
  return (
    <div>
      <input 
        value={localQuery}                    // ← Local state for immediate feedback
        onChange={(e) => setLocalQuery(e.target.value)} 
      />
      <select 
        value={per} 
        onChange={(e) => changePerPage(Number(e.target.value))}
      >
        {/* per-page options */}
      </select>
      
      {/* Render datasets... */}
      
      <button onClick={() => goToPage(page - 1)}>Previous</button>
      <button onClick={() => goToPage(page + 1)}>Next</button>
    </div>
  );
}
```

## Why This Architecture?

### ✅ Benefits

1. **Single Source of Truth**: URL contains all pagination/search state
2. **Browser Integration**: Back/forward buttons work correctly
3. **Bookmarkable**: URLs like `/datasets?q=test&page=2` work when shared
4. **Separation of Concerns**: URL management ≠ Data fetching
5. **Reusability**: Same hooks work for datasets, jobs, users, etc.
6. **Automatic Caching**: TanStack Query handles caching and deduplication
7. **Performance**: Debouncing prevents excessive API calls

### ⚠️ Potential Issues

1. **URL Pollution**: Many parameters can make URLs long
2. **Double Rendering**: Component renders twice (local state + URL update)
3. **Complexity**: New developers need to understand the flow
4. **Debounce Delay**: 300ms delay might feel slow for some users

### Possible Improvements

1. **Reduce Debounce Delay**: 150ms instead of 300ms
2. **Add URL Validation**: Ensure page/per are valid numbers
3. **Custom URL Structure**: Use `/datasets/search/test/page/2` instead of query params
4. **Virtualization**: For large lists, implement virtual scrolling
5. **Server Components**: Move to Next.js server components for better SEO
6. **State Libraries**: Consider Zustand/Jotai for complex shared state

The key insight is that **URL state management and data fetching are separate concerns** that work together through reactive programming principles.
