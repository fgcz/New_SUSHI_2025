# MultiOmicsStudio Authentication & User Management Analysis

This document analyzes the authentication, user management, and LDAP integration from the original Ruby SUSHI application and provides guidance for the MultiOmicsStudio implementation. It identifies pitfalls from organic growth in the legacy system and documents requirements that must be addressed.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Legacy Ruby System Analysis](#legacy-ruby-system-analysis)
3. [Current FastAPI Implementation Status](#current-fastapi-implementation-status)
4. [Critical Requirements Not Yet Implemented](#critical-requirements-not-yet-implemented)
5. [LDAP Schema Details](#ldap-schema-details)
6. [Authorization Model](#authorization-model)
7. [Course Mode Requirements](#course-mode-requirements)
8. [Implementation Guidance](#implementation-guidance)
9. [API Design Decisions](#api-design-decisions)
10. [Security Considerations](#security-considerations)

---

## Executive Summary

MultiOmicsStudio is a bioinformatics workflow management system that authenticates users against an LDAP directory (FGCZ). Users have access to **projects** based on their LDAP group memberships. A special class of users called **employees** (bioinformaticians) have access to ALL projects.

**Key architectural decision for the rewrite**: Project context will be URL-based (`/projects/{project_number}/...`) rather than session-based. This eliminates the complex state management that plagued the Ruby version.

**Authentication flow**: LDAP authentication → JWT tokens → Stateless API requests

---

## Legacy Ruby System Analysis

### Source Files Analyzed

| File | Purpose |
|------|---------|
| `app/controllers/application_controller.rb` | Main controller with auth setup |
| `app/helpers/application_helper.rb` | Employee checks, project initialization |
| `app/models/user.rb` | User model with Devise LDAP |
| `app/controllers/users/sessions_controller.rb` | Login/logout handling |
| `app/services/notification_service.rb` | Bioinformatician lookup |
| `config/initializers/devise.rb` | Devise LDAP configuration |
| `sandbox/fgcz.rb` | LDAP utility functions |
| `Gemfile` | Dependencies including forked gems |

### Identified Pitfalls and Anti-Patterns

#### 1. The `project_init` Monster Method

**Location**: `app/helpers/application_helper.rb:17-75`

The `project_init` method is a 60-line function with deeply nested conditionals that:
- Parses multiple URL parameter formats (`project_id`, `id`, `select_project`, `project[number]`)
- Writes to the database on almost every page navigation
- Mixes URL parsing, session management, authorization, and persistence
- Has at least 5 different code paths for determining the current project

```ruby
# This executes on every request and writes to DB:
current_user.selected_project = number
current_user.save
```

**Impact**:
- Unnecessary database writes on every navigation
- Extremely difficult to test
- Hard to reason about which code path executes
- Tight coupling between view helpers and database operations

**Lesson for FastAPI**: Use URL path parameters for project context. Never store "current project" in the database or session. The project number should be explicit in every API request URL.

---

#### 2. Scattered and Duplicated Authorization Logic

**Locations**:
- `app/helpers/application_helper.rb:5-6`
- `app/controllers/application_controller.rb:36-38`
- `app/services/notification_service.rb:46-51`

The `employee?` check is implemented in three different places with slight variations:

```ruby
# application_helper.rb
def employee?
  SushiFabric::Application.config.fgcz? and current_user and FGCZ.employee?(current_user.login)
end

# notification_service.rb
def employee?(user)
  return false unless user
  SushiFabric::Application.config.fgcz? && FGCZ.employee?(user.login)
end

# application_controller.rb
def employee?
  view_context.employee?  # Delegates to helper
end
```

**Impact**:
- DRY violation
- Risk of inconsistent behavior
- Each call potentially triggers an LDAP query
- No caching of employee status

**Lesson for FastAPI**: Determine employee status ONCE at login time. Cache it in the JWT token. Create a single `require_project_access()` dependency that handles all authorization.

---

#### 3. Hardcoded LDAP Configuration

**Location**: `sandbox/fgcz.rb:7-9`

```ruby
LDAP_SERVER = "fgcz-ldap.fgcz-net.unizh.ch"
LDAP_BASE = "DC=FGCZ-NET,DC=unizh,DC=ch"
LDAP_DN = "CN=${login},OU=OU_Applications,OU=OU_Accounts,DC=FGCZ-NET,DC=unizh,DC=ch"
```

**Impact**:
- Cannot deploy to different environments without code changes
- Cannot run integration tests against a test LDAP server
- Server URLs exposed in source code

**Lesson for FastAPI**: All LDAP configuration MUST come from environment variables. This is already correctly implemented in `app/core/config.py`.

---

#### 4. Forked and Outdated Dependencies

**Location**: `Gemfile:43`

```ruby
gem 'devise_ldap_authenticatable', '>= 0.8.6.1',
    :path => '/usr/local/ngseq/gems/devise_ldap_authenticatable_forked_20190712'
```

**Impact**:
- Deployment depends on specific server filesystem paths
- Fork is from 2019, likely contains unpatched security vulnerabilities
- Upgrades are impossible without understanding what was forked and why
- Creates "works on my machine" scenarios

**Lesson for FastAPI**: Use standard, maintained libraries (`ldap3`). If customization is needed, implement it in application code, not by forking libraries. Document any LDAP-specific workarounds clearly.

---

#### 5. No Caching of LDAP Results

The Ruby code calls LDAP methods like `FGCZ.employee?()` and `FGCZ.get_user_projects2()` on potentially every request. There is no caching layer.

**Impact**:
- LDAP server becomes a performance bottleneck
- Increased latency on every page load
- LDAP server availability becomes critical for every operation

**Lesson for FastAPI**: Cache LDAP results in the JWT token at login time. The token contains `projects` list and should also contain `is_employee` flag. On token refresh, optionally re-query LDAP to pick up permission changes.

---

#### 6. Mixed Authentication Modes with Global Conditionals

**Location**: `app/controllers/application_controller.rb:31-33`

```ruby
if SushiFabric::Application.config.fgcz?
  before_action :authenticate_user!
end
```

**Impact**:
- Two completely different runtime behaviors based on a config flag
- Hard to test both paths
- "Course mode" and "FGCZ mode" have divergent code paths scattered throughout

**Lesson for FastAPI**: Implement course mode as a proper authentication strategy, not as scattered conditionals. Create a dedicated course mode user provider that returns a synthetic user with preset permissions.

---

#### 7. User Model Stores Transient State

**Location**: `db/schema.rb` - User table has `selected_project` column

```ruby
t.integer  "selected_project", default: -1
```

**Impact**:
- Database writes on navigation
- State can become inconsistent with URL
- Complicates multi-tab usage (each tab might expect different project)

**Lesson for FastAPI**: Do NOT store selected project in the database. Project context comes from URL path. The User model should only store persistent identity data.

---

#### 8. Brittle Regex-Based LDAP Group Parsing

**Location**: `sandbox/fgcz.rb:35`

```ruby
group = value[/^CN=SG_([^,]+),/, 1]
```

Projects are extracted from LDAP group DNs using regex. Group names follow pattern `SG_p1234`.

**Impact**:
- If LDAP group naming conventions change, code breaks silently
- No validation of extracted values
- Regex is cryptic and undocumented

**Lesson for FastAPI**: Document the expected LDAP group naming convention clearly. Add validation and logging when parsing fails. Consider making the pattern configurable.

---

## Current FastAPI Implementation Status

### What Is Implemented

| Component | Status | Location |
|-----------|--------|----------|
| LDAP authentication | ✅ Basic | `app/core/ldap.py` |
| JWT access tokens | ✅ Complete | `app/core/security.py` |
| Refresh tokens | ✅ Complete | `app/repositories/refresh_token.py` |
| User sync from LDAP | ✅ Basic | `app/services/auth.py` |
| Login endpoint | ✅ Complete | `app/api/routes/auth.py` |
| Token refresh endpoint | ✅ Complete | `app/api/routes/auth.py` |
| Logout endpoints | ✅ Complete | `app/api/routes/auth.py` |
| Project access check | ⚠️ Partial | `app/api/deps.py` |
| Auth skip for dev | ✅ Complete | Uses `ENVIRONMENT=local` |

### What Is NOT Implemented

| Component | Status | Notes |
|-----------|--------|-------|
| Employee detection | ❌ Missing | LDAP group check not implemented |
| Employee bypass for all projects | ❌ Missing | `require_project_access` doesn't check employee status |
| Course mode | ❌ Missing | Only dev skip-auth exists |
| LDAP group pattern `SG_pXXXX` | ❌ Wrong | Current code expects `project_XXXX` pattern |
| Bioinformatician user lookup | ❌ Missing | Needed for notifications |
| `is_employee` in JWT | ❌ Missing | Not in token payload |
| `is_employee` in User model | ❌ Missing | Not in database schema |

---

## Critical Requirements Not Yet Implemented

### 1. Employee Status Detection

Employees (bioinformaticians) are identified by membership in specific LDAP groups. The Ruby code checks for groups matching pattern `SG_Bioinformat*`.

**Required behavior**:
- At login, check if user is member of employee groups
- Store `is_employee` flag in JWT token
- Employees can access ANY project without explicit membership

**Files to modify**:
- `app/core/ldap.py` - Add `_is_employee()` method
- `app/core/security.py` - Add `is_employee` to JWT payload
- `app/api/deps.py` - Update `require_project_access()` to bypass for employees

### 2. Correct LDAP Group Pattern

The current implementation expects groups named `project_XXXX`. The actual LDAP uses `SG_pXXXX` pattern.

**Required change in `app/core/ldap.py`**:
```python
# Current (incorrect):
if cn.startswith("project_"):
    project_num = int(cn.replace("project_", ""))

# Should be:
# Parse from memberOf attribute, groups are CN=SG_p1234,OU=...
match = re.match(r"^CN=SG_p(\d+),", group_dn, re.IGNORECASE)
if match:
    project_num = int(match.group(1))
```

### 3. Course Mode

Course mode allows the system to run without LDAP for training/demo purposes.

**Required behavior**:
- When `COURSE_MODE=true`, authentication returns a synthetic user
- Course user has access to predefined projects (`COURSE_PROJECTS` setting)
- Course user is NOT an employee (cannot see all projects)

**Configuration needed in `app/core/config.py`**:
```python
COURSE_MODE: bool = False
COURSE_PROJECTS: list[int] = [1001]  # Default project for demos
COURSE_USER_LOGIN: str = "course_user"
```

### 4. Authorization Dependency Update

The current `require_project_access()` in `app/api/deps.py` only checks if project is in user's list. It needs to also check employee status.

**Required logic**:
```python
def require_project_access(project_number: int, user: CurrentUser) -> None:
    # Employees can access all projects
    if user.is_employee:
        return

    # Regular users need explicit project membership
    if project_number not in user.projects:
        raise ForbiddenError(f"No access to project {project_number}")
```

---

## LDAP Schema Details

Based on analysis of the Ruby code, here is the LDAP schema used:

### User DN Pattern
```
CN={login},OU=OU_Applications,OU=OU_Accounts,DC=FGCZ-NET,DC=unizh,DC=ch
```

### Project Group Pattern
Groups follow naming convention `SG_p{number}`:
- `SG_p1001` = Project 1001
- `SG_p1535` = Project 1535

Users have `memberOf` attribute containing group DNs:
```
memberOf: CN=SG_p1001,OU=Groups,DC=FGCZ-NET,DC=unizh,DC=ch
memberOf: CN=SG_p1535,OU=Groups,DC=FGCZ-NET,DC=unizh,DC=ch
```

### Employee Group Pattern
Employees are members of groups starting with `SG_Bioinformat`:
```
memberOf: CN=SG_Bioinformatics,OU=Groups,DC=FGCZ-NET,DC=unizh,DC=ch
```

### Configuration Required

These settings must be added/updated in `.env`:

```bash
# LDAP Server
LDAP_HOST=ldap://fgcz-ldap.fgcz-net.unizh.ch:389
LDAP_BASE_DN=DC=FGCZ-NET,DC=unizh,DC=ch
LDAP_USER_SEARCH_BASE=OU=OU_Applications,OU=OU_Accounts,DC=FGCZ-NET,DC=unizh,DC=ch

# Group patterns (consider making these configurable)
# LDAP_PROJECT_GROUP_PATTERN=^CN=SG_p(\d+),
# LDAP_EMPLOYEE_GROUP_PATTERN=SG_Bioinformat
```

---

## Authorization Model

### User Types

| Type | Project Access | Identified By |
|------|----------------|---------------|
| Regular User | Only LDAP-assigned projects | Default |
| Employee | ALL projects | Member of `SG_Bioinformat*` group |
| Course User | Predefined list | `COURSE_MODE=true` |

### Authorization Flow

```
1. Request arrives: GET /projects/1234/datasets
                           │
2. Extract JWT from Authorization header
                           │
3. Decode JWT → {user_id, login, is_employee, projects}
                           │
4. Check project access:
   ├─ is_employee == true → ALLOW
   ├─ 1234 in projects → ALLOW
   └─ else → 403 Forbidden
                           │
5. Execute endpoint handler
```

### JWT Token Payload

Current payload:
```json
{
  "sub": "123",
  "login": "username",
  "projects": [1001, 1002],
  "exp": 1234567890,
  "iat": 1234567890,
  "type": "access"
}
```

Required payload (add `is_employee`):
```json
{
  "sub": "123",
  "login": "username",
  "is_employee": false,
  "projects": [1001, 1002],
  "exp": 1234567890,
  "iat": 1234567890,
  "type": "access"
}
```

Note: For employees, `projects` can be empty since they have access to all.

---

## Course Mode Requirements

Course mode is used for training sessions and demos where LDAP is not available.

### Behavior

1. **Authentication**: Skip LDAP, accept any credentials (or no credentials)
2. **User Identity**: Return a synthetic course user
3. **Project Access**: Limited to `COURSE_PROJECTS` list
4. **Employee Status**: Course user is NOT an employee

### Implementation Strategy

Do NOT scatter course mode conditionals throughout the code (Ruby's mistake). Instead:

1. Create a `CourseAuthService` that implements the same interface as `AuthService`
2. Use dependency injection to swap implementations based on `COURSE_MODE`
3. Course mode should be completely transparent to route handlers

```python
# In deps.py
def get_auth_service(...) -> AuthService:
    if settings.COURSE_MODE:
        return CourseAuthService()
    return AuthService(user_repo, refresh_token_repo, ldap_service)
```

### Course Mode Configuration

```python
# config.py
class Settings(BaseSettings):
    COURSE_MODE: bool = False
    COURSE_PROJECTS: str = "1001"  # Comma-separated
    COURSE_USER_LOGIN: str = "course_user"
    COURSE_USER_EMAIL: str = "course@example.com"

    @property
    def course_project_list(self) -> list[int]:
        return [int(p.strip()) for p in self.COURSE_PROJECTS.split(",")]
```

---

## Implementation Guidance

### Priority Order

1. **Fix LDAP group pattern** - Currently broken, uses wrong pattern
2. **Add employee detection** - Core authorization feature
3. **Update JWT payload** - Add `is_employee` flag
4. **Update authorization dependency** - Employee bypass
5. **Implement course mode** - Needed for demos/training

### Testing Strategy

Create test fixtures for:

1. **Regular user** - Has access to projects [1001, 1002]
2. **Employee user** - `is_employee=true`, should access any project
3. **Course user** - `is_employee=false`, projects from config
4. **User with no projects** - Edge case, should get 403 on all project endpoints

### LDAP Testing

For development and testing without a real LDAP server:

1. Use `ENVIRONMENT=local` with auth skip (current approach)
2. OR set up a local OpenLDAP container with test data
3. OR create a mock LDAP service for unit tests

```python
# tests/conftest.py
@pytest.fixture
def mock_ldap_service():
    service = Mock(spec=LDAPService)
    service.authenticate.return_value = {
        "login": "testuser",
        "email": "test@example.com",
        "projects": [1001, 1002],
        "is_employee": False,
    }
    return service
```

---

## API Design Decisions

### Project Context in URL (Not Session)

**Decision**: Project number is a URL path parameter, not stored in session or database.

**Rationale**:
- RESTful and stateless
- Supports multi-tab usage (different project per tab)
- Cacheable responses
- Clear authorization boundary
- Eliminates the `project_init` complexity from Ruby

**URL patterns**:
```
GET  /projects/{project_number}/datasets
GET  /projects/{project_number}/datasets/{dataset_id}
POST /projects/{project_number}/datasets
GET  /projects/{project_number}/jobs
```

### Token Refresh Strategy

**Decision**: On token refresh, do NOT re-query LDAP by default.

**Rationale**:
- Refresh should be fast
- LDAP availability shouldn't affect refresh
- Permission changes can wait until next full login

**Alternative consideration**: Add optional `force_ldap_refresh` parameter for cases where permissions might have changed.

### User Database Model

**Decision**: Store minimal user data locally. Do NOT store:
- Password (LDAP handles auth)
- Selected project (URL-based)
- Employee status long-term (cache in JWT only)

**User table should have**:
- `id` - Primary key
- `login` - LDAP username (unique)
- `email` - From LDAP

**Optional additions**:
- `is_employee` - Cached from LDAP, with `last_ldap_sync` timestamp
- `created_at`, `updated_at` - Audit fields

---

## Security Considerations

### Secrets Management

1. **JWT_SECRET_KEY** - Must be changed from default in production
2. **LDAP credentials** - If using admin bind, protect bind password
3. **Refresh tokens** - Stored as SHA256 hash, not plaintext

### Token Security

1. **Access tokens** - Short-lived (30 min default), in Authorization header
2. **Refresh tokens** - Long-lived (7 days), HttpOnly cookie, hashed in DB
3. **SameSite policy** - Strict, prevents CSRF

### LDAP Security

1. Use LDAPS (LDAP over TLS) in production
2. Bind with user credentials, not admin credentials when possible
3. Validate and sanitize username before constructing DN (prevent LDAP injection)

### Authorization Checks

1. ALWAYS check project access on project-specific endpoints
2. Use `require_project_access()` dependency consistently
3. Log authorization failures for security monitoring

---

## Appendix: Ruby Code Reference

Key files from the Ruby codebase for reference:

### LDAP Functions (from Ruby `fgcz` gem)

```ruby
# These methods need Python equivalents:
FGCZ.get_user_projects2(login)      # Returns ["p1001", "p1002"]
FGCZ.employee?(login)                # Returns true/false
FGCZ.get_bioinformatician_users     # Returns list of employee logins
FGCZ.get_user_groups(login, pass)   # Returns group names
```

### User Model (Ruby)

```ruby
class User < ActiveRecord::Base
  devise :ldap_authenticatable, :rememberable, :trackable

  has_many :data_sets
  has_one :notification_setting
  has_many :notifications

  # Fields: id, login, selected_project, sign_in tracking fields
end
```

### Session Data (Ruby)

```ruby
# Stored in session:
session[:employee]  # Boolean
session[:projects]  # Array of integers
session[:project]   # Currently selected project
session[:partition] # "course", "employee", or "user"
```

In FastAPI, all of this is in the JWT token instead.

---

## Document History

| Date | Author | Changes |
|------|--------|---------|
| 2025-04-07 | Analysis | Initial analysis of Ruby codebase and FastAPI status |

---

## Questions for Future Development

1. **Bioinformatician notifications**: The Ruby system can query LDAP for all bioinformaticians to send notifications. Is this feature needed? If so, add `get_bioinformatician_logins()` to LDAP service.

2. **Permission caching**: Should we cache employee status in the User database with a TTL, or always rely on JWT? Database caching survives token expiry but requires sync logic.

3. **Audit logging**: Should authentication events (login, logout, failed attempts) be logged to the database for security audit?

4. **Rate limiting**: Should login attempts be rate-limited to prevent brute force attacks?

5. **Session management UI**: Should users be able to see and revoke their active sessions (like "logout from all devices")?
