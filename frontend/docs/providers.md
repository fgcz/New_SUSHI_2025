# Application Providers

This document explains the two main providers that wrap the entire Sushi application in `app/layout.tsx`: **QueryProvider** and **AuthProvider**.

## QueryProvider

### Purpose
The `QueryProvider` wraps the entire application with TanStack Query (formerly React Query) functionality, enabling efficient server state management throughout the app.

### Location
- **File**: `providers/QueryProvider.tsx`
- **Wrapper**: Outermost provider in the layout hierarchy

### Configuration
```typescript
const [client] = useState(() => new QueryClient({
  defaultOptions: {
    queries: { 
      retry: 1,                    // Retry failed queries once
      refetchOnWindowFocus: false  // Don't refetch when window gains focus
    }
  }
}));
```

### What it Provides
- **Global Query Client**: Manages all API queries across the application
- **Caching**: Automatically caches API responses to reduce network requests
- **Background Updates**: Handles stale data updates and refetching
- **Loading States**: Provides consistent loading states for all queries
- **Error Handling**: Centralized error handling for API failures

### Usage Throughout App
Components use `useQuery` hook to fetch data:
```typescript
const { data, isLoading, error } = useQuery({
  queryKey: ['datasets', projectNumber],
  queryFn: () => projectApi.getProjectDatasets(projectNumber),
  staleTime: 60_000, // Data stays fresh for 1 minute
});
```

---

## AuthProvider

### Purpose
The `AuthProvider` manages user authentication state and provides authentication context throughout the entire application.

### Location
- **File**: `contexts/AuthContext.tsx`
- **Wrapper**: Inner provider (wrapped by QueryProvider)

### Key Features

#### 1. **Authentication Status Management**
- Fetches authentication configuration from backend
- Handles both authenticated and "authentication skipped" modes
- Stores current user information

#### 2. **JWT Token Handling**
- Stores JWT tokens in `localStorage`
- Automatically verifies token validity
- Clears invalid tokens
- Refreshes authentication state

#### 3. **Route Protection**
- Automatically redirects unauthenticated users to `/login`
- Monitors route changes and enforces authentication
- Skips protection when authentication is disabled

#### 4. **Authentication States**
```typescript
interface AuthContextType {
  authStatus: AuthenticationStatus | null;  // Current auth configuration
  loading: boolean;                         // Loading state
  error: string | null;                     // Error messages
  refetch: () => Promise<void>;            // Refresh auth status
  logout: () => void;                      // Logout function
}
```

### Authentication Flow

1. **App Initialization**
   ```
   AuthProvider loads → fetchAuthStatus() → Check backend config
   ```

2. **Authentication Skipped Mode**
   ```
   Backend returns authentication_skipped: true → User can access all routes
   ```

3. **Authentication Required Mode**
   ```
   Check localStorage for JWT → Verify with backend → Set user or redirect to login
   ```

4. **Route Changes**
   ```
   useEffect monitors pathname → Re-check auth on every route change
   ```

### Usage in Components
```typescript
import { useAuth } from '@/contexts/AuthContext';

function SomeComponent() {
  const { authStatus, loading, logout } = useAuth();
  
  if (loading) return <LoadingSpinner />;
  
  return (
    <div>
      <p>User: {authStatus?.current_user || 'Not logged in'}</p>
      <button onClick={logout}>Logout</button>
    </div>
  );
}
```

---

## Provider Hierarchy

The providers are nested in `app/layout.tsx` with specific order:

```typescript
<QueryProvider>          // Outermost - provides query functionality
  <AuthProvider>         // Inner - provides auth context
    {children}           // App content
  </AuthProvider>
</QueryProvider>
```


---

## Benefits

- **Consistent API patterns**: All components use the same query patterns
- **Automatic auth protection**: Routes are automatically protected without manual checks
- **Centralized state**: Authentication and data fetching logic is centralized
- **Type safety**: TypeScript interfaces ensure type-safe usage
- **Fast navigation**: Cached data makes page transitions instant
- **Seamless auth**: Automatic token management and route protection
- **Consistent UX**: Standardized loading states and error handling
- **Offline resilience**: Query caching provides some offline functionality

---

## Development Notes

- **QueryProvider** uses TanStack Query v4+ patterns with modern React practices
- **AuthProvider** integrates with Next.js router for seamless navigation
- Both providers use `'use client'` directive for client-side functionality
- Error boundaries should be implemented at route level to catch provider errors
- Authentication can be completely disabled via backend configuration
