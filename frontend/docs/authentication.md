# Frontend Authentication Architecture

This document explains how authentication works in the frontend, including state management, token handling, and the different authentication flows.

## 1. State Management (AuthContext)

**Location:** `providers/AuthContext.tsx`

The AuthContext is the central hub for authentication state in the application.

### State Held

| State | Type | Purpose |
|-------|------|---------|
| `authStatus` | `AuthState \| null` | Current authentication info |
| `loading` | `boolean` | True during auth checks |
| `error` | `string \| null` | Error message if auth fails |

### AuthState Structure

```typescript
interface AuthState {
  ldap_auth: boolean;           // From backend - is LDAP enabled?
  authentication_skipped: boolean;  // From backend - is dev mode?
  current_user: string | null;  // Username if logged in
}
```

### Exposed Functions

- `refetch()` - Manually re-check auth status
- `logout()` - Clear tokens and redirect to login

---

## 2. Token Storage

### Access Token

- **Storage:** `localStorage` as `jwt_token`
- **Management:** `httpClient.setToken()` / `httpClient.clearToken()`
- **Usage:** Sent as `Authorization: Bearer <token>` header on every API request
- **Contents:** `{sub: user_id, login: username, projects: [...]}`
- **Lifetime:** Short-lived (typically 30 minutes)

### Refresh Token

- **Storage:** HttpOnly cookie set by backend (frontend cannot read it)
- **Usage:** Automatically sent with requests via `credentials: 'include'`
- **Purpose:** Used by `/auth/refresh` endpoint to get new access token
- **Lifetime:** Long-lived (typically 7 days)

---

## 3. HTTP Client

**Location:** `lib/api/client.ts`

### Responsibilities

1. Attaches `Authorization` header if token exists
2. Sends cookies with every request (`credentials: 'include'`)
3. Handles 401 responses with automatic token refresh
4. Triggers `onUnauthorized` callback when refresh fails

### 401 Handling with Token Refresh

When a request receives a 401 response:

1. **Skip for auth endpoints** - `/auth/*` endpoints don't trigger refresh (avoid loops)
2. **Try refresh** - Call `POST /auth/refresh` using the HttpOnly refresh token cookie
3. **On success** - Store new access token, retry the original request
4. **On failure** - Call `onUnauthorized()` handler (logout + redirect)

### Concurrent Request Handling

If multiple requests fail with 401 simultaneously, they share a single refresh call via `refreshPromise`. This prevents multiple refresh requests from racing.

---

## 4. Initialization Flow (App Mount)

```typescript
useEffect(() => {
  httpClient.setUnauthorizedHandler(handleUnauthorized);
  fetchAuthStatus();
}, []);
```

### fetchAuthStatus() Sequence

1. Call `GET /auth/login_options`
   - Returns `{ldap_auth, authentication_skipped}`

2. Call `GET /auth/me`
   - Success → set `current_user` from response
   - Failure → set `current_user = null`

3. If no user AND `authentication_skipped = false` AND not on `/login`:
   - Redirect to `/login`

---

## 5. Authentication Branches

### Branch 1: Dev Mode (SKIP_AUTH=true on backend)

```
/auth/login_options → {authentication_skipped: true}
/auth/me (no token) → {login: "dev_user"}  ← backend returns this automatically
Result: current_user = "dev_user", app loads normally
```

### Branch 2: Production, Valid Token

```
/auth/login_options → {authentication_skipped: false}
/auth/me (with token) → {login: "actual_user"}
Result: current_user = "actual_user", app loads normally
```

### Branch 3: Production, No Token

```
/auth/login_options → {authentication_skipped: false}
/auth/me → 401 Unauthorized
Result: current_user = null, redirect to /login
```

### Branch 4: Token Expires Mid-Session (Refresh Succeeds)

```
User makes API request → 401 Unauthorized
httpClient calls POST /auth/refresh (uses HttpOnly cookie)
Backend returns new access_token
httpClient stores new token, retries original request
Result: Request succeeds, user continues working
```

### Branch 5: Token Expires, Refresh Token Also Expired

```
User makes API request → 401 Unauthorized
httpClient calls POST /auth/refresh
Backend returns 401 (refresh token expired/revoked)
httpClient triggers onUnauthorized()
Result: logout(), redirect to /login
```

---

## 6. Login Flow

**Location:** `app/login/page.tsx`

1. User submits username and password
2. Frontend calls `POST /auth/login {username, password}`
3. Backend returns `{access_token, user}`
4. `httpClient.setToken(access_token)` → saves to localStorage
5. Backend sets `refresh_token` as HttpOnly cookie
6. Frontend redirects to home
7. On next mount, AuthContext fetches auth status

---

## 7. Logout Flow

1. User clicks logout button
2. `authApi.logout()` is called:
   - Calls `POST /auth/logout` (backend revokes refresh token)
   - Calls `httpClient.clearToken()` (removes from localStorage)
3. `setAuthStatus(null)` clears React state
4. Redirect to `/login`

---

## 8. Frontend Skip Logic

**The frontend has NO skip logic of its own.**

Everything is driven by backend responses:

- `authentication_skipped` flag comes from backend
- `dev_user` identity comes from backend `/auth/me`
- Frontend treats all modes the same way

The only frontend-side exception:
- 401 handler ignores `/auth/*` endpoints to avoid redirect loops during initial auth check

---

## 9. Data Location Summary

| Data | Location | Set By | Read By |
|------|----------|--------|---------|
| Access token | localStorage | `authApi.login()` | `httpClient.request()` |
| Refresh token | HttpOnly cookie | Backend | Backend only |
| Auth status | React state | `fetchAuthStatus()` | Any component via `useAuth()` |
| 401 handler | httpClient instance | AuthContext on mount | httpClient on 401 |

---

## 10. Sequence Diagram

```
┌─────────┐          ┌──────────┐          ┌─────────┐
│ Browser │          │ Frontend │          │ Backend │
└────┬────┘          └────┬─────┘          └────┬────┘
     │                    │                     │
     │  Visit App         │                     │
     │───────────────────>│                     │
     │                    │                     │
     │                    │ GET /login_options  │
     │                    │────────────────────>│
     │                    │                     │
     │                    │ {authentication_skipped, ldap_auth}
     │                    │<────────────────────│
     │                    │                     │
     │                    │ GET /auth/me        │
     │                    │────────────────────>│
     │                    │                     │
     │                    │ {login, projects}   │
     │                    │<────────────────────│
     │                    │                     │
     │  Render App        │                     │
     │<───────────────────│                     │
     │                    │                     │
```
