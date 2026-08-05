# Loading Patterns for Components
**Last Updated:** 2026-03-19

This document explains React's rendering cycle, how data fetching triggers re-renders, and the loading patterns we use in this codebase.

## React Rendering Cycle

### How React Renders

React components are functions that return JSX. When a component's **state** or **props** change, React calls the function again (re-renders) to get the new JSX.

```
State/Props Change → React calls component function → New JSX → DOM updates
```

### What Triggers a Re-render

1. **useState setter called** - `setState(newValue)`
2. **Props change** - Parent passes different values
3. **Context change** - Provider value updates
4. **useQuery data arrives** - TanStack Query updates internal state

### The Render Loop with Data Fetching

When using `useQuery`, a component typically renders **multiple times**:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1st Render: Initial Mount                                       │
│    - useQuery returns: { data: undefined, isLoading: true }     │
│    - Component shows: Loading skeleton                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    (API request in flight)
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2nd Render: Data Arrives                                        │
│    - useQuery returns: { data: {...}, isLoading: false }        │
│    - Component shows: Actual content                            │
└─────────────────────────────────────────────────────────────────┘
```

### Multiple Hooks = Multiple Re-renders

If a component uses multiple `useQuery` hooks, it re-renders each time one completes:

```tsx
function DatasetPage({ id }) {
  const { data: dataset, isLoading: isDatasetLoading } = useDatasetBase(id);
  const { data: samples, isLoading: isSamplesLoading } = useDatasetSamples(id);

  // This component will render AT LEAST 3 times:
  // 1. Initial: both loading
  // 2. Dataset arrives: dataset loaded, samples still loading
  // 3. Samples arrive: both loaded
}
```

This is **normal and expected behavior** - not a bug.

## Our Loading Pattern: Early Return

We use the **early return pattern** to show loading states and prevent rendering child components before data is ready.

### Basic Pattern

```tsx
export default function SomePage() {
  const { data, isLoading, error } = useQuery({...});

  // 1. Loading state - show skeleton
  if (isLoading) {
    return <PageSkeleton />;
  }

  // 2. Error state - show error message
  if (error) {
    return <ErrorDisplay error={error} />;
  }

  // 3. Success state - render content
  return (
    <div>
      <h1>{data.title}</h1>
      {/* ... */}
    </div>
  );
}
```


### Gate Pattern for Child Components

The early return acts as a **gate** - child components don't mount until data is ready:

```tsx
function ParentPage() {
  const { data, isLoading } = useQuery({...});

  if (isLoading) {
    return <Skeleton />;  // ChildComponent does NOT exist yet
  }

  return <ChildComponent data={data} />;  // ChildComponent mounts with valid data
}

function ChildComponent({ data }) {
  // Safe to assume data exists - parent gates us
  return <div>{data.name}</div>;
}
```

## Skeleton Components

We use skeleton loaders to show the page structure while loading.

### Skeleton Design Principles

1. **Match the layout** - Skeleton should resemble final content shape
2. **Animate** - Use `animate-pulse` for visual feedback
3. **Appropriate sizing** - Match expected content dimensions

### Skeleton Placement

Skeletons are defined in the same file as the page component:

```
app/projects/[projectNumber]/datasets/
├── page.tsx              # Contains both DatasetsPage and DatasetsPageSkeleton
```


### Loading vs Fetching

| State | When | Use For |
|-------|------|---------|
| `isLoading` | First load, no cached data | Show skeleton |
| `isFetching` | Any request in flight | Show subtle indicator |
| `!isLoading && isFetching` | Refetching with cached data | Dim content, show spinner |

## Summary

| Pattern | When to Use |
|---------|-------------|
| Early return with skeleton | Page-level loading |
| Combined `isLoading` | Multiple data dependencies |
| `placeholderData: keepPreviousData` | Pagination, filtering |
| Gate pattern | Child components need parent data |
| Skeleton components | Visual loading feedback |

## Related Documentation

- [Multiple UI Triggers](./multiple-ui-triggers.md) - Deep dive into re-render behavior
- [State Management](./state-management.md) - TanStack Query configuration
- [Architecture](./architecture.md) - Page structure patterns
