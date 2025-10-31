# Testing Layers Overview

## API Layer Testing

API layer tests validate the raw HTTP client functions in `/lib/api/*.ts` that handle URL construction, HTTP methods, request bodies, and response parsing. These tests ensure that correct requests are sent to the backend and responses are properly parsed into TypeScript types.

## Hook Layer Testing  

Hook layer tests validate the React Query integration that wraps API functions with caching, loading states, error handling, and data transformation. These tests ensure that hooks correctly manage React state, refetch data when dependencies change, and handle the component lifecycle properly.

## Why Both Layers Matter

API functions and hooks can work correctly in isolation but fail when integrated together due to timing issues, state management conflicts, or user interaction patterns. Page integration tests are essential to validate complete user workflows and catch issues that individual layer tests might miss.

## Testing Focus Areas

### API Layer (`lib/api/*.test.ts`)
- URL construction with correct parameters
- HTTP method selection (GET, POST, PUT, DELETE)
- Request body formatting
- Response parsing and error handling
- Network failure scenarios

### Hook Layer (`lib/hooks/**/*.test.ts`)
- Loading and error state management
- Data caching and invalidation
- Query refetching when dependencies change
- Hook lifecycle and React integration
- Disabled query handling

### Integration Layer (`app/**/*.test.tsx`)
- Complete user workflows (search → filter → paginate)
- Multi-component interactions
- URL parameter synchronization
- Real-time data updates and user feedback