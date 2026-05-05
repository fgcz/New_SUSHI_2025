# Files API: Directory Listing

The Files API provides directory listing for the gstore file system, allowing users to browse project files and folders.

---

## Overview

**Endpoint:** `GET /files/{path}`

**Base Directory:** `/srv/gstore/projects` (configured via `GSTORE_DIR`)

**Example:**
```
GET /files/p1234                → list project root
GET /files/p1234/analysis       → list analysis subfolder
GET /files/p1234/data/file.bam  → returns file info (not download)
```

---

## Access Control

Access to files is controlled by project membership:

| User Type | Access |
|-----------|--------|
| **Project member** | Can access files in projects they belong to |
| **Employee** (`is_employee=true`) | Global read access to all projects |
| **Other** | 403 Forbidden |

The project number is extracted from the path (e.g., `p1234/...` → project 1234).

---

## Response Format

### Directory Listing

```json
{
  "items": [
    {
      "name": "sample1.fastq.gz",
      "type": "file",
      "size": 1234567890,
      "modified": "2024-03-15T10:30:00+00:00"
    },
    {
      "name": "analysis",
      "type": "directory",
      "size": null,
      "modified": "2024-03-14T08:00:00+00:00"
    }
  ],
  "pagination": {
    "total": 150,
    "page": 1,
    "per_page": 50,
    "total_pages": 3
  }
}
```

### Query Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `page` | 1 | Page number (1-indexed) |
| `per_page` | 50 | Items per page |
| `sort_by` | `name` | Sort field: `name`, `modified`, `size` |
| `sort_desc` | `false` | Sort descending |

---

## Security

### Path Validation

The API validates paths to prevent directory traversal attacks:

```python
def validate_path(path: str) -> bool:
    # Block empty path
    if not path:
        return False
    # Block path traversal
    if ".." in path:
        return False
    # Block absolute paths
    if path.startswith("/"):
        return False
    # Must start with project pattern
    if not re.match(r"^p\d+", path):
        return False
    return True
```

**Rejected paths:**
- `../etc/passwd` → contains `..`
- `/srv/gstore/projects/p1234` → absolute path
- `data/files` → doesn't start with `p{number}`

---

## Known Limitations and Design Decisions

### Symlinks

**Behavior:** Symlinks are followed transparently.

**Risk:** A symlink inside a project could point outside the gstore directory, potentially exposing unintended files.

**Mitigation options (not currently implemented):**
1. Resolve symlinks and check if target is within gstore
2. Skip symlinks entirely
3. Mark symlinks as a special type in the response

**Current status:** This follows the Ruby SUSHI behavior. The risk is accepted since project directories are admin-controlled.

### File Clicks / Downloads

**Current behavior:** The API only returns file metadata (name, size, modified date). It does not serve file content.

**File downloads** should be handled separately, potentially via:
- Direct nginx/Apache serving with auth headers
- A dedicated download endpoint with streaming

### Large Directories

Directories with thousands of files are handled via pagination. The full listing is cached in memory, so very large directories (100k+ files) may cause memory pressure.

### Permissions Errors

Files that cannot be `stat()`'d (permission denied, broken symlinks) are silently skipped rather than causing the entire listing to fail.

---

## Caching

The service implements LRU caching with time-based invalidation:

| Setting | Value |
|---------|-------|
| Cache size | 256 directories |
| TTL | 30 seconds |
| Invalidation | Time-bucket based |

**How it works:**
```python
@lru_cache(maxsize=256)
def _list_directory_cached(directory: str, cache_bucket: int):
    # cache_bucket changes every 30 seconds, invalidating old entries
    ...
```

**Cache management:**
```python
from app.services.files import clear_cache, get_cache_info

# Clear all cached listings
clear_cache()

# Get cache statistics
info = get_cache_info()
# {"hits": 150, "misses": 20, "size": 45, "maxsize": 256}
```

---

## Implementation

### Service Layer

**Location:** `app/services/files.py`

| Function | Purpose |
|----------|---------|
| `list_directory()` | Main entry point with pagination/sorting |
| `validate_path()` | Security validation |
| `extract_project_number()` | Parse `p1234` from path |
| `clear_cache()` | Clear directory cache |
| `get_cache_info()` | Cache statistics |

### Route Layer

**Location:** `app/api/routes/files.py` (TODO)

The route should:
1. Validate the path
2. Extract project number
3. Check access via `require_project_access()`
4. Call `list_directory()` service
5. Return paginated response

---

## Comparison with Ruby SUSHI

| Aspect | Ruby SUSHI | Python SUSHI |
|--------|------------|--------------|
| Caching | None | LRU with TTL |
| Pagination | In-memory slice | In-memory slice |
| Path validation | Basic | Regex-based |
| Symlink handling | Follow | Follow |
| Access control | Session-based | JWT + `is_employee` |

---

## Configuration

Infrastructure paths are configured in `app/core/config.py`:

```python
GSTORE_DIR: str = "/srv/gstore/projects"  # Override via .env
```

Override in `.env`:
```bash
GSTORE_DIR=/path/to/your/gstore
```
