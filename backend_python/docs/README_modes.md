# SUSHI Environment Modes and Configuration Analysis

This document analyzes how the original Ruby SUSHI application handles different deployment modes (production, demo, course, test, development) and provides guidance for architecting the Python/FastAPI rewrite to avoid the pitfalls discovered through organic growth.

---

## Table of Contents

1. [Overview of the Problem](#overview-of-the-problem)
2. [Ruby Mode Architecture](#ruby-mode-architecture)
3. [What Each Mode Does](#what-each-mode-does)
4. [Where It Got Ugly](#where-it-got-ugly)
5. [Impact Analysis](#impact-analysis)
6. [Lessons Learned](#lessons-learned)
7. [Recommended Architecture for FastAPI](#recommended-architecture-for-fastapi)
8. [Configuration Strategy](#configuration-strategy)
9. [Feature Flags vs. Modes](#feature-flags-vs-modes)
10. [Testing Considerations](#testing-considerations)

---

## Overview of the Problem

SUSHI needs to run in multiple contexts:

| Context | Authentication | File Storage | Job Submission | External Services |
|---------|---------------|--------------|----------------|-------------------|
| **Production** | LDAP required | Enterprise storage (gstore) | HPC cluster (g-req) | BFabric integration |
| **Demo** | LDAP required | Simplified storage | Direct rsync | No BFabric |
| **Course** | LDAP required | Simplified storage | Limited nodes | No BFabric |
| **Development** | Optional | Local filesystem | Mock/local | Mocked |
| **Test** | Mocked | Temp directories | Mocked | Mocked |

The Ruby codebase evolved to handle these modes through **scattered conditionals** rather than a clean abstraction, leading to code that is hard to understand, test, and extend.

---

## Ruby Mode Architecture

### Mode Detection Mechanism

The Ruby app uses **hostname detection** to determine if it's running on FGCZ infrastructure:

```
production.rb:
  def config.fgcz?
    @fgcz ||= (`hostname`.chomp =~ /fgcz/)
  end
```

This creates a binary split: **FGCZ mode** (on their servers) vs **non-FGCZ mode** (everywhere else).

### The Four Server Classes

The Ruby app defines four "server classes" that handle file operations differently:

| Class | File Operations | Used When |
|-------|-----------------|-----------|
| `ProdSushi` | `g-req copy` (enterprise queue system) | Production on FGCZ |
| `TestSushi` | Same as ProdSushi | Testing on FGCZ infrastructure |
| `DemoSushi` | Simple `rsync` | Demos on FGCZ |
| `CourseSushi` | Same as DemoSushi | Training courses |

Note: `TestSushi = ProdSushi` and `CourseSushi = DemoSushi` are literally aliases.

### Configuration Locations

Mode is controlled by **editing source code** in `config/environments/production.rb`:

```ruby
# To switch modes, uncomment/comment these lines:
config.sushi_server_class = "SushiFabric::TestSushi"    # current
#config.sushi_server_class = "SushiFabric::ProdSushi"   # for production
#config.sushi_server_class = "SushiFabric::DemoSushi"   # for demo
#config.sushi_server_class = "SushiFabric::CourseSushi" # for course
config.course_mode = false  # or true for course mode
```

This means **deploying a different mode requires code changes**, not configuration changes.

---

## What Each Mode Does

### Production Mode

**Detection**: Hostname contains "fgcz" + `sushi_server_class = ProdSushi`

**Characteristics**:
- Full LDAP authentication required
- Files stored in `/srv/gstore/projects`
- File operations use `g-req` queue system (enterprise job scheduler for file transfers)
- Datasets registered in BFabric (external lab management system)
- Users assigned to "employee" or "user" partition for job scheduling
- Full HPC cluster access

**Unique behaviors in code**:
- BFabric registration commands are executed
- `g-req copynow` / `g-req copy` for file transfers
- Module loading from FGCZ lmod system
- Employee status checked via LDAP

### Demo Mode

**Detection**: Hostname contains "fgcz" + `sushi_server_class = DemoSushi`

**Characteristics**:
- LDAP authentication still required (on FGCZ network)
- Files stored in `/srv/GT/analysis/course_sushi/public/gstore/projects`
- File operations use simple `rsync`
- No BFabric registration
- Same user partitions as production

**Purpose**: Lighter-weight demos without enterprise file transfer overhead.

### Course Mode

**Detection**: Hostname contains "fgcz" + `sushi_server_class = CourseSushi` + `course_mode = true`

**Characteristics**:
- LDAP authentication required
- Same file handling as Demo mode
- `session[:partition]` forced to "course" for all users
- Compute nodes may be restricted (commented-out code suggests limiting to specific nodes)
- Users get projects from `config.course_users` setting (if defined)

**Purpose**: Training sessions with controlled environment.

### Non-FGCZ Mode (Development)

**Detection**: Hostname does NOT contain "fgcz"

**Characteristics**:
- Authentication not enforced (`before_action :authenticate_user!` skipped)
- FGCZ gem not loaded
- Files stored in `./public/gstore/projects` (local)
- Server class may be undefined or TestSushi
- BFabric integration disabled
- Default project [1001] assigned to users

**Purpose**: Local development without FGCZ infrastructure.

---

## Where It Got Ugly

### Problem 1: Hostname-Based Detection

The fundamental mode detection uses shell command execution:

```ruby
@fgcz ||= (`hostname`.chomp =~ /fgcz/)
```

**Issues**:
- Cannot override without changing hostname
- Cannot run production-like tests locally
- Mode is implicit, not explicit
- Requires knowledge of FGCZ naming conventions

### Problem 2: Scattered Conditionals

The `config.fgcz?` check appears **23+ times** across the codebase:

| File | Occurrences | What It Guards |
|------|-------------|----------------|
| `application_controller.rb` | 3 | Gem loading, authentication, file saving |
| `application_helper.rb` | 4 | Employee check, project list, session init |
| `data_set_controller.rb` | 4 | View flag for templates |
| `home_controller.rb` | 2 | View flag, file serving |
| `data_set.rb` (model) | 1 | BFabric registration |
| `project.rb` (model) | 1 | BFabric registration |
| `notification_service.rb` | 2 | Employee/bioinformatician lookup |
| View templates | 5+ | UI elements, download links |

Each location implements its own logic for "what to do when fgcz". There's no single place that defines "FGCZ mode behavior".

### Problem 3: Mode Changes Require Code Edits

To switch from production to course mode:

1. SSH into server
2. Edit `config/environments/production.rb`
3. Change `sushi_server_class` line
4. Change `course_mode` line
5. Change `gstore_dir` line
6. Restart application

This is error-prone and not suitable for automated deployments.

### Problem 4: Coupled Concerns

The `fgcz?` flag controls multiple independent concerns:
- Authentication (required or not)
- File storage backend (gstore vs local)
- File transfer method (g-req vs rsync)
- External service integration (BFabric)
- User role system (employee/user/course)
- UI elements (download links, support email)

These should be independently configurable but are all tied to one boolean.

### Problem 5: Missing Abstraction for File Operations

Instead of a proper interface, file operations are handled by class inheritance:

```ruby
class DemoSushi < SushiServerClass
  def copy_commands(org_dir, dest_parent_dir, now=nil, queue="light")
    commands = ["rsync -r #{org_dir} #{dest_parent_dir}/"]
  end
end

class ProdSushi < SushiServerClass
  def copy_commands(org_dir, dest_parent_dir, now=nil, queue="light")
    # Complex g-req logic...
  end
end
```

The class is selected by **string evaluation**:

```ruby
@@sushi_server = eval(SushiFabric::Application.config.sushi_server_class).new
```

Using `eval()` on config is a security risk and makes the code hard to trace.

### Problem 6: Course Mode is Incomplete

The `course_users` configuration is referenced but never defined in visible config files:

```ruby
elsif SushiFabric::Application.config.course_mode and
      user_projects_ = SushiFabric::Application.config.course_users
```

This suggests course mode was partially implemented or the config is set elsewhere (possibly in a file not in version control).

### Problem 7: Views Depend on Mode

Templates check `@fgcz` flag to show/hide UI elements:

```erb
<% if @fgcz and current_user and current_user.login %>
  <!-- FGCZ-specific download links with scp commands -->
<% end %>
```

This tightly couples the view layer to deployment mode.

---

## Impact Analysis

### What Breaks When You Change Modes

| Change | Risk |
|--------|------|
| Moving to new server | Hostname detection fails, wrong mode |
| Running locally | No authentication, different file paths |
| Testing production behavior | Must mock hostname or deploy to FGCZ |
| Adding new mode | Must find and update all 23+ conditionals |
| Changing file storage | Scattered gstore_dir references |

### Technical Debt Accumulated

1. **No unit tests for mode behavior** - Can't test FGCZ mode without FGCZ infrastructure
2. **No integration tests for modes** - Each mode is a different runtime
3. **Documentation scattered** - Comments in production.rb are the only docs
4. **Knowledge silos** - Only developers who know "fgcz" understand the modes

---

## Lessons Learned

### Lesson 1: Mode Should Be Explicit Configuration

**Ruby mistake**: Detect mode from hostname
**Better approach**: Explicit `MODE=production|demo|course|development|test` environment variable

### Lesson 2: Separate Concerns Into Independent Settings

**Ruby mistake**: One `fgcz?` flag controls authentication, storage, transfers, and UI
**Better approach**: Independent settings for each concern:
```
AUTH_PROVIDER=ldap|none|mock
STORAGE_BACKEND=gstore|local|s3
FILE_TRANSFER=g-req|rsync|copy
BFABRIC_ENABLED=true|false
```

### Lesson 3: Use Dependency Injection, Not Conditionals

**Ruby mistake**: `if config.fgcz?` scattered everywhere
**Better approach**: Inject the appropriate service implementation at startup

### Lesson 4: Abstract External Services

**Ruby mistake**: Direct calls to `FGCZ.employee?()` in multiple places
**Better approach**: Define interfaces (protocols/ABCs) and inject implementations

### Lesson 5: Don't Use eval() for Configuration

**Ruby mistake**: `eval(SushiFabric::Application.config.sushi_server_class).new`
**Better approach**: Factory pattern with explicit mapping

### Lesson 6: Keep Views Mode-Agnostic

**Ruby mistake**: `<% if @fgcz %>` in templates
**Better approach**: API provides capability flags, frontend adapts

---

## Recommended Architecture for FastAPI

### Mode Configuration

Define mode as explicit environment variable:

```bash
# .env
SUSHI_MODE=production  # production, demo, course, development, test
```

### Separate Concern Settings

```bash
# Authentication
AUTH_ENABLED=true
AUTH_PROVIDER=ldap  # ldap, mock, none
LDAP_HOST=ldap://fgcz-ldap.fgcz-net.unizh.ch:389

# Storage
STORAGE_BACKEND=gstore  # gstore, local, s3
GSTORE_DIR=/srv/gstore/projects

# File Transfer
FILE_TRANSFER_METHOD=g-req  # g-req, rsync, local-copy

# External Services
BFABRIC_ENABLED=true
BFABRIC_API_URL=https://bfabric.example.com

# Course Mode Specifics
COURSE_MODE=false
COURSE_PROJECTS=1001,1002
COURSE_USER_LOGIN=course_user
```

### Service Abstraction with Protocols

```python
# app/core/protocols.py
from typing import Protocol

class FileTransferService(Protocol):
    """Interface for file transfer operations."""

    def copy(self, source: str, destination: str) -> None:
        """Copy files from source to destination."""
        ...

    def delete(self, target: str) -> None:
        """Delete files at target path."""
        ...

class AuthProvider(Protocol):
    """Interface for authentication."""

    def authenticate(self, username: str, password: str) -> dict:
        """Authenticate user and return user info."""
        ...

    def get_user_projects(self, username: str) -> list[int]:
        """Get projects accessible by user."""
        ...

    def is_employee(self, username: str) -> bool:
        """Check if user is an employee."""
        ...
```

### Implementation Selection via Factory

```python
# app/core/factories.py
from app.core.config import settings

def get_file_transfer_service() -> FileTransferService:
    """Factory for file transfer service based on configuration."""
    if settings.FILE_TRANSFER_METHOD == "g-req":
        from app.services.file_transfer.greq import GReqFileTransfer
        return GReqFileTransfer()
    elif settings.FILE_TRANSFER_METHOD == "rsync":
        from app.services.file_transfer.rsync import RsyncFileTransfer
        return RsyncFileTransfer()
    else:
        from app.services.file_transfer.local import LocalFileTransfer
        return LocalFileTransfer()

def get_auth_provider() -> AuthProvider:
    """Factory for auth provider based on configuration."""
    if not settings.AUTH_ENABLED:
        from app.services.auth.noop import NoopAuthProvider
        return NoopAuthProvider()
    elif settings.AUTH_PROVIDER == "ldap":
        from app.services.auth.ldap import LDAPAuthProvider
        return LDAPAuthProvider()
    elif settings.AUTH_PROVIDER == "mock":
        from app.services.auth.mock import MockAuthProvider
        return MockAuthProvider()
    else:
        raise ValueError(f"Unknown auth provider: {settings.AUTH_PROVIDER}")
```

### Dependency Injection in Routes

```python
# app/api/deps.py
from fastapi import Depends
from app.core.factories import get_file_transfer_service, get_auth_provider

FileTransferDep = Annotated[FileTransferService, Depends(get_file_transfer_service)]
AuthProviderDep = Annotated[AuthProvider, Depends(get_auth_provider)]
```

### Mode Presets

For convenience, define mode presets that set multiple settings:

```python
# app/core/config.py
class Settings(BaseSettings):
    SUSHI_MODE: str = "development"

    # Individual settings with defaults
    AUTH_ENABLED: bool = True
    AUTH_PROVIDER: str = "ldap"
    STORAGE_BACKEND: str = "local"
    FILE_TRANSFER_METHOD: str = "local-copy"
    BFABRIC_ENABLED: bool = False
    COURSE_MODE: bool = False

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._apply_mode_presets()

    def _apply_mode_presets(self):
        """Apply default settings based on SUSHI_MODE."""
        presets = {
            "production": {
                "AUTH_ENABLED": True,
                "AUTH_PROVIDER": "ldap",
                "STORAGE_BACKEND": "gstore",
                "FILE_TRANSFER_METHOD": "g-req",
                "BFABRIC_ENABLED": True,
            },
            "demo": {
                "AUTH_ENABLED": True,
                "AUTH_PROVIDER": "ldap",
                "STORAGE_BACKEND": "gstore",
                "FILE_TRANSFER_METHOD": "rsync",
                "BFABRIC_ENABLED": False,
            },
            "course": {
                "AUTH_ENABLED": True,
                "AUTH_PROVIDER": "ldap",
                "STORAGE_BACKEND": "gstore",
                "FILE_TRANSFER_METHOD": "rsync",
                "BFABRIC_ENABLED": False,
                "COURSE_MODE": True,
            },
            "development": {
                "AUTH_ENABLED": False,
                "STORAGE_BACKEND": "local",
                "FILE_TRANSFER_METHOD": "local-copy",
                "BFABRIC_ENABLED": False,
            },
            "test": {
                "AUTH_ENABLED": False,
                "AUTH_PROVIDER": "mock",
                "STORAGE_BACKEND": "local",
                "FILE_TRANSFER_METHOD": "local-copy",
                "BFABRIC_ENABLED": False,
            },
        }
        # Apply preset defaults, but allow env vars to override
        # (Implementation detail: check if explicitly set before applying)
```

---

## Configuration Strategy

### Environment Variable Hierarchy

```
1. Explicit environment variable (highest priority)
2. Mode preset default
3. Global default (lowest priority)
```

Example:
- `SUSHI_MODE=production` sets `AUTH_ENABLED=true` by default
- But `AUTH_ENABLED=false` in env explicitly overrides

### Configuration Validation

```python
# app/core/config.py
from pydantic import field_validator

class Settings(BaseSettings):
    @field_validator("SUSHI_MODE")
    def validate_mode(cls, v):
        valid_modes = ["production", "demo", "course", "development", "test"]
        if v not in valid_modes:
            raise ValueError(f"SUSHI_MODE must be one of {valid_modes}")
        return v

    @field_validator("FILE_TRANSFER_METHOD")
    def validate_transfer_method(cls, v):
        valid = ["g-req", "rsync", "local-copy"]
        if v not in valid:
            raise ValueError(f"FILE_TRANSFER_METHOD must be one of {valid}")
        return v
```

### Startup Validation

```python
# app/main.py
from app.core.config import settings

def validate_configuration():
    """Validate configuration at startup."""
    errors = []

    if settings.AUTH_PROVIDER == "ldap" and not settings.LDAP_HOST:
        errors.append("LDAP_HOST required when AUTH_PROVIDER=ldap")

    if settings.STORAGE_BACKEND == "gstore" and not settings.GSTORE_DIR:
        errors.append("GSTORE_DIR required when STORAGE_BACKEND=gstore")

    if settings.FILE_TRANSFER_METHOD == "g-req":
        # Check if g-req command is available
        if not shutil.which("g-req"):
            errors.append("g-req command not found but FILE_TRANSFER_METHOD=g-req")

    if errors:
        raise RuntimeError(f"Configuration errors: {errors}")

# Call at startup
validate_configuration()
```

---

## Feature Flags vs. Modes

### When to Use Modes

Modes are appropriate when:
- Multiple settings change together
- The combination represents a deployment scenario
- Users think in terms of "I'm deploying for X purpose"

### When to Use Feature Flags

Feature flags are appropriate when:
- A single capability can be toggled independently
- The feature might be enabled/disabled within a mode
- You want to gradually roll out functionality

### Example Feature Flags

```bash
# These are independent of mode
FEATURE_NOTIFICATIONS_ENABLED=true
FEATURE_JOB_MONITORING_ENABLED=true
FEATURE_DATASET_EXPORT_ENABLED=false  # Not yet ready
```

---

## Testing Considerations

### Testing Different Modes

```python
# tests/conftest.py
import pytest
from app.core.config import Settings

@pytest.fixture
def production_settings():
    """Settings configured for production mode."""
    return Settings(
        SUSHI_MODE="production",
        LDAP_HOST="ldap://test-ldap:389",
        GSTORE_DIR="/tmp/test-gstore",
    )

@pytest.fixture
def development_settings():
    """Settings configured for development mode."""
    return Settings(SUSHI_MODE="development")

@pytest.fixture
def course_settings():
    """Settings configured for course mode."""
    return Settings(
        SUSHI_MODE="course",
        COURSE_PROJECTS="1001,1002",
    )
```

### Testing Service Implementations

```python
# tests/services/test_file_transfer.py
import pytest
from app.services.file_transfer.rsync import RsyncFileTransfer
from app.services.file_transfer.local import LocalFileTransfer

class TestRsyncFileTransfer:
    def test_copy_generates_correct_command(self, tmp_path):
        service = RsyncFileTransfer()
        # Test that it generates correct rsync command
        ...

class TestLocalFileTransfer:
    def test_copy_copies_files(self, tmp_path):
        service = LocalFileTransfer()
        # Test actual file copy
        ...
```

### Mock Services for Unit Tests

```python
# tests/mocks.py
class MockFileTransfer:
    def __init__(self):
        self.copies = []
        self.deletes = []

    def copy(self, source: str, destination: str) -> None:
        self.copies.append((source, destination))

    def delete(self, target: str) -> None:
        self.deletes.append(target)

class MockAuthProvider:
    def __init__(self, users: dict = None):
        self.users = users or {
            "testuser": {
                "projects": [1001, 1002],
                "is_employee": False,
            }
        }

    def authenticate(self, username: str, password: str) -> dict:
        if username in self.users:
            return {"login": username, **self.users[username]}
        raise AuthenticationError("Invalid credentials")
```

---

## API Capabilities Endpoint

Instead of views checking `@fgcz`, provide a capabilities API:

```python
# app/api/routes/system.py
@router.get("/capabilities")
def get_capabilities() -> dict:
    """Return system capabilities based on current configuration."""
    return {
        "authentication": {
            "enabled": settings.AUTH_ENABLED,
            "provider": settings.AUTH_PROVIDER,
        },
        "features": {
            "bfabric_integration": settings.BFABRIC_ENABLED,
            "enterprise_file_transfer": settings.FILE_TRANSFER_METHOD == "g-req",
            "course_mode": settings.COURSE_MODE,
        },
        "download_methods": _get_download_methods(),
    }

def _get_download_methods() -> list[str]:
    """Return available download methods based on config."""
    methods = ["http"]
    if settings.STORAGE_BACKEND == "gstore":
        methods.append("scp")
        methods.append("rsync")
    return methods
```

Frontend can then adapt its UI based on capabilities without hardcoding mode checks.

---

## Summary: Do's and Don'ts

### Do

- Use explicit `SUSHI_MODE` environment variable
- Separate concerns into independent settings
- Define interfaces (protocols) for external services
- Use dependency injection
- Provide mode presets for convenience
- Validate configuration at startup
- Test each service implementation independently
- Expose capabilities via API for frontend

### Don't

- Detect mode from hostname or other implicit signals
- Scatter `if mode == X` conditionals throughout code
- Use `eval()` for dynamic class loading
- Couple authentication, storage, and UI to single flag
- Require code changes to switch modes
- Put mode checks in view templates
- Assume services are available without checking

---

## Migration Path

For gradual adoption in the FastAPI rewrite:

1. **Phase 1**: Implement explicit `SUSHI_MODE` setting
2. **Phase 2**: Create `AuthProvider` protocol and implementations
3. **Phase 3**: Create `FileTransferService` protocol and implementations
4. **Phase 4**: Add `/capabilities` endpoint
5. **Phase 5**: Implement mode presets
6. **Phase 6**: Add configuration validation

Each phase can be completed independently and tested before moving to the next.

---

## Document History

| Date | Author | Changes |
|------|--------|---------|
| 2025-04-07 | Analysis | Initial analysis of Ruby mode architecture |
