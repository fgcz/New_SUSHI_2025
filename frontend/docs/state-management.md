# State Management and Data Persistence Between Pages

This document explains how we handle state management and data persistence between pages in the Sushi frontend application.

## Overview

When users navigate between pages in a multi-step workflow (like job submission), we need to preserve form data and application state. This document covers different approaches and their trade-offs.

## Approaches for Data Persistence

### 1. Local Storage (Current Choice)

Local Storage is our preferred method for persisting large form data between pages.

#### Implementation

```typescript
// Storing data before navigation
const formData = {
  nextDataset: { name: "...", comment: "..." },
  parameters: { param1: "value1", param2: "value2" }
};

localStorage.setItem('jobSubmissionData', JSON.stringify(formData));
router.push('/confirm');

// Retrieving data on the destination page
const storedData = localStorage.getItem('jobSubmissionData');
const formData = storedData ? JSON.parse(storedData) : {};
```

#### Pros
- Handles large data (5-10MB browser limit)
- Simple implementation
- Persists across tab refreshes and browser restarts
- No server round-trips required
- Works in client-side rendering

#### Cons
- Data persists after session ends (privacy consideration)
- Not available during Server-Side Rendering (SSR)
- Lost if user clears browser data
- Not shareable between devices/users
- Requires manual cleanup

#### Best Practices
1. **Clear data after use**: Always remove localStorage items when no longer needed
2. **Handle missing data**: Always check if data exists and provide fallbacks
3. **Use prefixed keys**: Use descriptive, prefixed keys to avoid conflicts
4. **Error handling**: Wrap localStorage operations in try-catch blocks

```typescript
// Good example with error handling and cleanup
try {
  const key = 'sushi_job_submission_data';
  localStorage.setItem(key, JSON.stringify(formData));
  
  // Navigate to confirmation page
  router.push('/confirm');
  
  // Later, on the confirmation page
  const data = JSON.parse(localStorage.getItem(key) || '{}');
  
  // Clean up after successful submission
  localStorage.removeItem(key);
} catch (error) {
  console.error('localStorage operation failed:', error);
  // Handle fallback behavior
}
```

### 2. React Context (Alternative for App-Wide State)

React Context is suitable for application-wide state that needs to be shared across components.

#### Implementation

```typescript
// Create context
interface JobDataContextType {
  jobData: JobSubmissionData | null;
  setJobData: (data: JobSubmissionData) => void;
  clearJobData: () => void;
}

const JobDataContext = createContext<JobDataContextType | undefined>(undefined);

// Provider component
export function JobDataProvider({ children }: { children: ReactNode }) {
  const [jobData, setJobDataState] = useState<JobSubmissionData | null>(null);
  
  const setJobData = useCallback((data: JobSubmissionData) => {
    setJobDataState(data);
  }, []);
  
  const clearJobData = useCallback(() => {
    setJobDataState(null);
  }, []);
  
  return (
    <JobDataContext.Provider value={{ jobData, setJobData, clearJobData }}>
      {children}
    </JobDataContext.Provider>
  );
}

// Custom hook
export function useJobData() {
  const context = useContext(JobDataContext);
  if (!context) {
    throw new Error('useJobData must be used within JobDataProvider');
  }
  return context;
}
```

#### Pros
- Type-safe with TypeScript
- React-native approach
- Automatic memory cleanup
- Good integration with component lifecycle
- Suitable for complex state management

#### Cons
- **Lost on page refresh** (major limitation)
- Requires context setup across the application
- Memory usage while data is stored
- More complex for simple data passing
- Not suitable for multi-step workflows that survive page refreshes

### 3. Server-Side Session Storage (Enterprise Option)

For applications requiring server-side data persistence, session storage can be implemented.

#### Implementation

```typescript
// API route: /api/job-session
export async function POST(request: Request) {
  const formData = await request.json();
  const sessionId = generateSessionId();
  
  // Store in server-side cache/database
  await redis.setex(`job_session:${sessionId}`, 3600, JSON.stringify(formData));
  
  return NextResponse.json({ sessionId });
}

// Client usage
const response = await fetch('/api/job-session', {
  method: 'POST',
  body: JSON.stringify(formData)
});
const { sessionId } = await response.json();
router.push(`/confirm?session=${sessionId}`);
```

#### Pros
- Server-side storage (unlimited size)
- Secure (not accessible from client)
- Works with SSR
- Automatic cleanup possible
- Shareable via session ID

#### Cons
- More complex implementation
- Requires session management infrastructure
- Server memory/storage usage
- Additional API endpoints needed
- Network latency for data operations

## Decision Matrix

| Use Case | Local Storage | React Context | Server Session |
|----------|---------------|---------------|----------------|
| Form data between pages | ✅ Recommended | ❌ Lost on refresh | ✅ Complex setup |
| App-wide UI state | ❌ Overkill | ✅ Recommended | ❌ Overkill |
| Sensitive data | ⚠️ Client-visible | ⚠️ Client-visible | ✅ Secure |
| Large datasets | ✅ Good | ❌ Memory usage | ✅ Unlimited |
| Simple implementation | ✅ Simple | ⚠️ Moderate | ❌ Complex |
| Page refresh survival | ✅ Survives | ❌ Lost | ✅ Survives |

## Implementation Guidelines

### For Job Submission Workflow

We use Local Storage for the job submission workflow because:

1. **Data size**: Job parameters can be large (file paths, complex configurations)
2. **User experience**: Users expect data to survive page refreshes
3. **Simplicity**: No server-side infrastructure required
4. **Performance**: No network round-trips for data retrieval

### Cleanup Strategy

```typescript
// Clean up localStorage on successful completion
const handleJobSubmissionSuccess = () => {
  localStorage.removeItem('sushi_job_submission_data');
  router.push('/jobs'); // Navigate to jobs list
};

// Clean up on component unmount (optional)
useEffect(() => {
  return () => {
    // Only clean up if user navigates away without completing
    if (!jobCompleted) {
      localStorage.removeItem('sushi_job_submission_data');
    }
  };
}, []);
```

### Error Handling

```typescript
const useLocalStorageState = <T>(key: string, defaultValue: T) => {
  const [state, setState] = useState<T>(() => {
    try {
      const item = localStorage.getItem(key);
      return item ? JSON.parse(item) : defaultValue;
    } catch {
      return defaultValue;
    }
  });

  const setStoredState = (value: T) => {
    try {
      setState(value);
      localStorage.setItem(key, JSON.stringify(value));
    } catch (error) {
      console.error(`Failed to save to localStorage:`, error);
      setState(value); // Update state even if storage fails
    }
  };

  return [state, setStoredState] as const;
};
```

## Security Considerations

1. **Don't store sensitive data** in localStorage (passwords, tokens, etc.)
2. **Validate and sanitize** data retrieved from localStorage
3. **Set reasonable expiration** by including timestamps
4. **Clear data** when no longer needed
5. **Consider encryption** for sensitive application data

## Testing Considerations

- Test behavior when localStorage is disabled
- Test data persistence across page refreshes
- Test cleanup scenarios
- Mock localStorage in unit tests
- Test error scenarios (quota exceeded, parse errors)

## Migration Path

If localStorage becomes insufficient, the migration path would be:

1. **Short term**: Add compression to reduce data size
2. **Medium term**: Implement hybrid approach (metadata in localStorage, large data on server)
3. **Long term**: Full server-side session management with Redis/database