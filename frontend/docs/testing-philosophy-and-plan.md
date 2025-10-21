# How to Run Tests

### Available Test Commands
```bash
# Basic test running
npm run test                # Run all tests once
npm run test:watch          # Run tests in watch mode (re-runs on file changes)
npm run test:coverage       # Run tests with coverage report
npm run test:ci             # Run tests in CI mode (no watch, with coverage)
```

### Test File Patterns
Jest automatically discovers and runs files matching these patterns:
- `**/__tests__/**/*.{js,jsx,ts,tsx}`
- `**/*.{test,spec}.{js,jsx,ts,tsx}`

### Test File Organization
We use **co-located testing** where test files live next to the code they test (e.g., `useSearch.ts` and `useSearch.test.ts` in the same directory). This approach makes tests easy to find and maintain alongside the implementation.

For specialized testing scenarios, we use descriptive file naming:
- **Basic tests**: `page.test.tsx`, `useSearch.test.ts`
- **Specialized tests**: `page.accessibility.test.tsx`, `useSearch.edge-cases.test.ts`
- **Mock variations**: `datasets.error-state.test.ts` (uses custom MSW handlers to simulate API errors)


## Testing Technology Overview


### Testing Technology Layer Stack
Understanding how these technologies work together is crucial for effective testing:

```
┌─────────────────────────────┐
│    Your Test Code           │ ← You write: getByText('hello'), expect().toBe()
├─────────────────────────────┤
│ React Testing Library (RTL) │ ← Provides: getByText, render, fireEvent, user-event
├─────────────────────────────┤  
│ jsdom                       │ ← Provides: document, window, DOM APIs, browser simulation
├─────────────────────────────┤
│ Jest                        │ ← Provides: test runner, expect, mocks, coverage
├─────────────────────────────┤
│ Node.js                     │ ← Runtime environment where tests execute
└─────────────────────────────┘
```

**User Interaction Methods - fireEvent vs user-event:**

**fireEvent (built into RTL)** - Direct event triggering:
```javascript
// Directly fires a synthetic click event
fireEvent.click(button);
fireEvent.change(input, { target: { value: 'hello' } });
```

**user-event (separate package)** - Realistic user simulation:
```javascript
// Simulates the complete user interaction sequence
await user.click(button);        // focus → mousedown → mouseup → click
await user.type(input, 'hello'); // focus → keydown → keypress → input → keyup (per character)
await user.tab();                // keyboard navigation between elements
```

**Key differences:**
- **fireEvent**: Fast, direct event dispatch - good for simple interactions
- **user-event**: Realistic user behavior simulation - better for complex workflows and accessibility testing
- **Timing**: fireEvent is synchronous, user-event is asynchronous (returns promises)
- **Event sequence**: fireEvent triggers single events, user-event triggers complete interaction sequences  
   

## MSW (Mock Service Worker) Data Flow

### How MSW Creates Realistic Testing Without Real Servers

MSW intercepts HTTP requests at the network layer, creating the illusion of a real API without actually running a server. Here's how the data flows through our testing ecosystem:

**The Interception Process:**
```
Your Component Code
    ↓ fetch('/api/v1/projects/1001/datasets?datasetName=RNA')
Network Layer (MSW intercepts here) ← The magic happens here!
    ↓ routes to matching handler function
Mock Handler Function (handlers.ts)
    ↓ processes real request parameters
    ↓ returns mock HttpResponse.json(data)
Back to Your Component
    ↓ receives realistic mock data
Component renders as if talking to real API
```

MSW sits between your application code and the actual network, capturing real HTTP requests and routing them to handler functions that return mock responses. Your components have no idea they're talking to fake APIs - they behave exactly like in production.

### renderWithQuery Wrapper Explained

The `renderWithQuery` function solves a critical problem: React Query components need a `QueryClientProvider` context to function. Without it, any component using `useQuery` hooks would crash during testing.

**Problem without wrapper:**
```typescript
// ❌ This crashes - no React Query context available
test('dataset page loads data', () => {
  render(<DatasetPage />)  // Error: useQuery must be used within QueryClientProvider
})
```

**Solution with renderWithQuery:**
```typescript
// ✅ This works - provides required React Query context
test('dataset page loads data', () => {
  renderWithQuery(<DatasetPage />)  // Component can safely use useQuery hooks
})
```

The wrapper creates a fresh React Query client configured for testing (no retries, no caching between tests) and wraps your component with the necessary provider context.

### Complete Data Flow Example

Here's how a typical test flows through the entire MSW and React Query ecosystem:

```typescript
test('search filters datasets by name', async () => {
  // 1. Render component with React Query context
  renderWithQuery(<DatasetPage />)
  
  // 2. Component mounts, useProjectDatasets hook executes
  // 3. Hook triggers: fetch('/api/v1/projects/1001/datasets')
  // 4. MSW intercepts this HTTP request before it leaves the app
  // 5. MSW matches URL pattern and routes to handler in handlers.ts
  // 6. Handler function receives real request object with URL parameters
  // 7. Handler processes parameters and returns HttpResponse.json(mockDatasets)
  // 8. React Query receives mock response as if from real API
  // 9. React Query updates component state with mock data
  // 10. Component re-renders displaying mock datasets
  
  // 11. Test verifies the rendered content
  const datasets = await screen.findByText('RNA-seq Analysis Dataset')
  expect(datasets).toBeInTheDocument()
  
  // 12. User interaction triggers new API call
  const searchInput = screen.getByPlaceholderText('Filter name...')
  await user.type(searchInput, 'RNA')
  
  // 13. New HTTP request: fetch('/api/v1/projects/1001/datasets?datasetName=RNA')
  // 14. MSW intercepts again, handler filters mock data by name
  // 15. Component receives filtered results and re-renders
  // 16. Test verifies filtered content appears
}
```

### MSW Files Structure

The `mocks/` directory contains the MSW configuration that enables this request interception:

- **`handlers.ts`** - Defines API endpoint responses (e.g., `GET /api/v1/projects/:id/datasets`) and contains the logic for filtering mock data based on request parameters
- **`server.ts`** - Sets up MSW for the Node.js testing environment with Jest lifecycle hooks (`beforeAll`, `afterEach`, `afterAll`)
- **`data/`** - Contains realistic mock data files (`datasets.ts`, `jobs.ts`) that handlers return, structured to match your actual API responses

MSW intercepts HTTP requests made by your existing `/lib/api` client functions and routes them to these handlers, which return controlled mock responses without requiring any changes to your application code. MSW is only active during testing (`npm run test`) and does not affect your development or production environments.

### Coverage of Frontend Testing Scenarios
This technology stack comprehensively covers all frontend testing needs:

- **Component Rendering**: Verify components render correctly with different props and states
- **User Interactions**: Test clicks, form submissions, keyboard navigation, and complex user workflows  
- **State Management**: Test React hooks, context providers, and state updates through user actions
- **API Integration**: Mock HTTP requests and test loading states, error handling, and data display
- **Routing & Navigation**: Test Next.js page navigation and URL parameter handling
- **Accessibility**: Ensure components work with screen readers and keyboard navigation
- **Performance**: Test component behavior under different data loads and user interaction patterns

---

## Testing Levels & Strategies

### 1. Unit Tests (Components & Functions)

#### **What to Test**
- **Custom hooks** (useSearch, usePagination, useProjectDatasets)
- **Utility functions** (API clients, data transformers, formatters)
- **Component behavior** (rendering, user interactions, prop variations)
- **Business logic** (filtering, pagination, validation)

#### **Component Testing Principles**
- **Test user interactions**: clicks, form submissions, keyboard navigation
- **Test accessibility**: screen reader content, ARIA attributes
- **Test error states**: loading, error, empty states
- **Avoid implementation details**: internal state, method calls

### 2. Integration Tests (Page-Level)

#### **What to Test**
- **Complete page workflows** (search → filter → paginate)
- **React Query integration** (loading states, error handling, cache behavior)
- **Multiple component interactions** (forms + tables + pagination)
- **Route navigation and parameter handling**

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] **Upgrade test infrastructure**
  - Create shared test utilities
  - Set up visual regression testing (optional)
  
- [ ] **Establish testing standards**
  - Create testing style guide

### Phase 2: Hook & Utility Testing (Week 2-3)
- [ ] **Custom hooks** (High Value)
  - `useSearch` - URL parameter management
  - `usePagination` - Page state handling  
  - `useProjectDatasets` - Data fetching with filters
  - `useAuth` - Authentication state

- [ ] **API layer** (Critical)
  - `projectApi` - Dataset and project operations
  - `jobApi` - Job management operations
  - `httpClient` - Base HTTP client functionality

### Phase 3: Component Testing (Week 3-4)
- [ ] **Core components** (High Impact)
  - Search components with debouncing
  - Pagination controls
  - Data tables with sorting/filtering
  - Form components with validation

- [ ] **Page components** (Integration)
  - Dataset list page workflow
  - Job list page workflow
  - Authentication flows

### Phase 4: Advanced Testing (Week 4-5)

- [ ] **Accessibility testing**
  - Screen reader compatibility
  - Keyboard navigation
  - ARIA attributes and roles
 
- [ ] **Performance testing**
  - Large dataset rendering
  - Search debouncing behavior
  - Memory leak detection

