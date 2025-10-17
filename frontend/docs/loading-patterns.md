# Suspense vs loading.tsx vs if-else

## loading.tsx
- Shows while Next.js downloads/executes page.tsx component
- Disappears as soon as page.tsx returns ANY JSX (loading div or content)
- Only useful on slow connections or heavy bundles
- Timeline: navigation -> loading.tsx -> page renders -> loading.tsx gone

## if-else vs Suspense - Same User Experience

```tsx
// if-else: manual control
{isLoading ? <Loading /> : <Content />}

// Suspense: automatic promise catching  
<Suspense fallback={<Loading />}>
  <ComponentThatThrows />
</Suspense>
```

## Key Differences

**if-else**: Manual boolean state management  
**Suspense**: Automatic promise catching with error boundaries  
**loading.tsx**: Next.js navigation loading, unrelated to data loading  

Both if-else and Suspense achieve same UX. Suspense provides cleaner code organization and automatic error handling.

## Priority-Based Loading Strategy

### Dataset Info: High Priority (if-else loading)
- **Critical content**: Users need dataset metadata first
- **Blocking approach**: Nothing else renders until dataset loads
- **User expectation**: Page feels "broken" without core dataset info
- **Fast loading**: Usually <1s, acceptable to block

### Runnable Apps: Lower Priority (Suspense)
- **Secondary content**: Nice-to-have feature exploration
- **Progressive enhancement**: Page is functional without apps
- **User tolerance**: Users can wait while exploring dataset info
- **Slower loading**: Potentially 2-5s, shouldn't block page

### Why Not Suspense for Dataset?
- Dataset info is the **primary page purpose**
- Empty page with skeleton feels unresponsive
- Users expect immediate feedback about the dataset they clicked
- Critical navigation context (breadcrumbs, title, description)

### Why Not if-else for Apps?
- Apps are **exploratory features**
- Dataset page is useful without them
- Suspense allows progressive page reveal
- Better perceived performance (content appears incrementally)

## Timing Reality: No Performance Difference

**Important**: Suspense vs if-else loading takes the **exact same time**.

```tsx
// Both approaches show content at identical moment
{isLoading ? <Loading /> : <Content />}  // Shows content when isLoading = false
<Suspense fallback={<Loading />}><Content /></Suspense>  // Shows content when promise resolves
```

## Complex Page State Management Pattern

### Multi-Query Dataset Detail Page (`/projects/[id]/datasets/[id]/page.tsx`)

This page demonstrates a sophisticated loading state pattern with **4 independent queries** and **multiple UI states**:

#### Query Architecture
```tsx
// Primary data (blocks page render)
const { data, isLoading: isDatasetLoading, error: datasetError } = useQuery({...});

// Secondary data (renders independently)  
const { data: runnableApps, isLoading: isRunnableAppsLoading, error: runnableAppsError } = useQuery({...});
const { data: datasetTree, isLoading: isDatasetTreeLoading, error: datasetTreeError } = useQuery({...});
const { data: datasetSamples, isLoading: isDatasetSamplesLoading, error: datasetSamplesError } = useQuery({...});
```

#### State Hierarchy Chain

1. **Initial Loading State** (`isDatasetLoading = true`)
   ```tsx
   // Full page skeleton with breadcrumb, title, and card placeholders
   ```

2. **Primary Error State** (`datasetError = true`)
   ```tsx
   // Error message with navigation back
   ```

3. **Data Not Found State** (`!dataset` after successful load)
   ```tsx
   // Dataset exists in response but not found by ID
   ```

4. **Success State with Progressive Loading** (Primary data loaded, secondary data loading)
   
   **Page Structure Renders Immediately:**
   - ✅ Breadcrumbs with real data
   - ✅ Page title with dataset name  
   - ✅ Basic dataset information (ID, name, created date, etc.)
   
   **Secondary Sections Load Independently:**

   **a) Folder Structure Section**
   ```tsx
   {isDatasetTreeLoading && !datasetTree ? (
     // Tree skeleton while loading
   ) : datasetTreeError ? (
     // Tree error state
   ) : datasetTree ? (
     // Tree success state
   ) : (
     // Tree empty state
   )}
   ```

   **b) Samples Section** (4 states: loading, error, success, empty)
   ```tsx
   {isDatasetSamplesLoading && !datasetSamples ? (
    // Samples skeleton while loading
   ) : datasetSamplesError ? (
     // Samples error state
   ) : datasetSamples && datasetSamples.length > 0 ? (
     // Full data table with dynamic columns
   ) : (
     // Empty samples state
   )}
   ```

   **c) Runnable Applications Section** (4 states: loading, error, success, empty)
   ```tsx
   {isRunnableAppsLoading && !runnableApps ? (
    // Apps skeleton while loading
   ) : runnableAppsError ? (
     // Apps error state
   ) : runnableApps && runnableApps.length > 0 ? (
     // Apps grouped by category with action buttons
   ) : (
     // Empty apps state
   )}
   ```

#### Progressive Enhancement Strategy

**Immediate Value (Blocking)**
- Core dataset metadata loads first
- Page navigation and context immediately available
- User can understand what dataset they're viewing

**Progressive Loading (Non-blocking)**  
- Folder structure, samples, and apps load independently
- Each section shows appropriate loading state
- User can interact with loaded sections while others load
- Failed sections don't break the overall page experience

#### State Matrix Summary

| Section | Loading | Error | Success | Empty |
|---------|---------|-------|---------|-------|
| **Primary Dataset** | Full page skeleton | Error page + back link | Renders page structure | "Not Found" page |
| **Folder Tree** | Tree skeleton | Red error box | Interactive tree | Empty state with icon |
| **Samples** | Table skeleton | Red error box | Dynamic data table | Empty state with icon |
| **Apps** | Category skeletons | Red error box | Category + action buttons | Empty state with icon |

This pattern provides **immediate user value** while **progressively enhancing** the page with additional features, creating an optimal user experience even under varying network conditions.

## Hook-Based Loading Architecture

#### Hook Responsibilities
- **Data fetching** - Moved to hooks
- **Business logic** - Moved to hooks
- **State computation** - Moved to hooks

#### Loading State Architecture
**Component Level: Presentation States**
```tsx
function DatasetDetailPage() {
  const { dataset, isLoading, error, notFound } = useDatasetBase(projectNumber, datasetId);
  
  // Primary loading states (blocking)
  if (isLoading) return <DatasetDetailSkeleton />;
  if (error) return <DatasetError error={error} />;
  if (notFound) return <DatasetNotFound />;
  
  // Success state with progressive loading
  return (
    <div>
      <DatasetHeader dataset={dataset} />
      <DatasetInfo dataset={dataset} />
      <AsyncDatasetTree datasetId={datasetId} />      {/* Self-contained loading */}
      <AsyncDatasetSamples datasetId={datasetId} />   {/* Self-contained loading */}
      <AsyncDatasetApps datasetId={datasetId} />      {/* Self-contained loading */}
    </div>
  );
}
```

#### Benefits of Hook-Based Loading

- 🧠 **Reduced cognitive load** - Components focus on presentation
- 🧪 **Testable business logic** - Test hooks independently from UI
- 🎯 **Better UX consistency** - Standardized loading behaviors
- 📦 **Smaller components** - 400-line pages become 200-line pages
- 🔍 **Easier debugging** - Data logic separated from UI logic
- 🚀 **Faster development** - Reuse existing hooks for new features

#### File Organization

```
app/feature/page.tsx                 # 150-200 lines: presentation + layout
├── components/                      # Complex UI sections
│   ├── FeatureSection.tsx          # Self-contained section components
│   └── AsyncFeatureWidget.tsx     # Async loading wrapper components
└── hooks/                          # Page-specific hooks
    └── useFeaturePageData.ts       # Page composition logic

lib/hooks/                          # Reusable domain hooks
├── dataset/
│   ├── useDatasetBase.ts           # Core dataset data
│   ├── useDatasetOperations.ts     # CRUD operations
│   └── useDatasetValidation.ts     # Business rules
└── shared/
    ├── useAsyncSection.ts          # Generic async loading wrapper
    └── useDebounce.ts              # Utility hooks
```

This architecture creates a **clear separation** between data concerns (hooks) and presentation concerns (components), making the codebase more maintainable while preserving the excellent user experience of progressive loading.

## Multi-Layer Architecture Benefits

Each layer in this design has a **single, focused responsibility**:

- **🔌 API Layer**: "How to make HTTP requests" - handles endpoints, request formatting, and response parsing
- **🎣 Hook Layer**: "How to manage React state for this data" - handles caching, loading states, business logic, and computed properties
- **📱 UI Layer**: "How to render this data" - handles presentation, user interactions, and layout


**Components should be primarily concerned with presentation**, not data fetching or business logic:
This separation ensures that **components remain simple and focused**, while **complex data logic is centralized** in testable, reusable hooks. The result is a more maintainable codebase that follows modern React architecture principles and industry best practices.
