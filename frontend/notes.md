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

## Suspense Implementation (Simplified)

```tsx
class Suspense extends Component {
  state = { hasPromise: false };
  
  componentDidCatch(error) {
    if (error instanceof Promise) {
      this.setState({ hasPromise: true });
      error.then(() => this.setState({ hasPromise: false }));
    }
  }
  
  render() {
    return this.state.hasPromise ? this.props.fallback : this.props.children;
  }
}

// Component throws promise when loading
function MyComponent() {
  if (isLoading) throw queryPromise; // Suspense catches this
  return <div>Content</div>;
}
```

## Timeline Comparison

### Early Return (All-or-Nothing)
- 0-2s: "Loading dataset..."
- 2s: Full page appears

### Suspense with Priorities (Progressive)
- 0-2s: "Loading dataset..." 
- 2-5s: Dataset info + "Loading apps..."
- 5s: Everything visible

## Composable Suspense Boundaries

```tsx
<Suspense fallback={<PageSkeleton />}>
  <Header />
  <Suspense fallback={<DatasetSkeleton />}>
    <DatasetInfo />
    <Suspense fallback={<AppsSkeleton />}>
      <RunnableApps />
    </Suspense>
  </Suspense>
</Suspense>
```

Each boundary catches promises independently. Content streams in progressively as data becomes available.

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

### So Why Choose One Over the Other?

The choice isn't about speed - it's about **code organization** and **composition**:

**if-else Benefits:**
- Explicit control over loading states
- Clear boolean logic flow
- Easier to debug loading conditions
- Better for critical, blocking content

**Suspense Benefits:**
- Automatic error boundary integration
- Composable loading boundaries
- Cleaner component separation
- Better for progressive content loading
- Handles nested async dependencies automatically

**Real Reason for Dataset if-else:**
- Not about performance
- About **explicit control** over critical page state
- Dataset loading failure needs specific error handling
- Clear intentional blocking behavior for core content
