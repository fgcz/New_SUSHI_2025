# Ruby vs Python Implementation Comparison

This document provides a comprehensive comparison between the original Ruby SUSHI implementation and the Python replacement for the files/directory listing API.

---

## 1. Route Structure

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Route pattern | `GET /projects/:project_id(/*dirs)` | `GET /files/{path:path}` | **Different** |
| Example | `/projects/p1234/analysis` | `/files/p1234/analysis` | Different prefix |
| File download | Same route with `.ext` format | Not implemented | **GAP** |

**Note:** Ruby uses `/projects/` prefix which overlaps with project management. Python uses `/files/` for clarity.

---

## 2. Directory Listing

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Listing method | `Dir[path + "/*"]` | `Path.iterdir()` | Equivalent |
| Fields returned | name, type, mtime, size | name, type, modified, size, size_bytes | **Match** |
| Size for dirs | `"-"` string | `"-"` string | **Match** |
| Size for files | Human-readable | Human-readable + raw bytes | **Match** |
| Date format | Ruby Time object | ISO 8601 string | Different (OK) |
| Hidden files | Included | Included | Match |
| Symlinks | Followed (implicit) | Followed (implicit) | Match |

---

## 3. Pagination

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Default page size | 10 | 50 | **Different** |
| Page size options | 10, 50, 100, 300 | 1-500 (any) | Python more flexible |
| State storage | Session (server-side) | Query params (stateless) | **Different approach** |
| URL format | `/projects/p1234/1:Name` | `/files/p1234?page=1&sort_by=name` | **Different** |

**Python advantage:** Stateless pagination is more RESTful and cacheable.

---

## 4. Sorting

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Sort fields | Name, Last_Modified, Size | name, modified, size | Match |
| Default sort (project root) | mtime descending | mtime descending | **Match** |
| Default sort (subdirs) | filesystem order | name ascending | Improved |
| Sort direction toggle | Session-based toggle | `sort_desc` param | Stateless (better) |
| In-memory sort | Yes (all files loaded) | Yes (all files loaded) | Match |

---

## 5. Access Control

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Employee check | `session[:employee]` | `user.is_employee` (JWT) | Match (different storage) |
| Project list | `session[:projects]` | `user.projects` (JWT) | Match (different storage) |
| Access logic | employee OR project member | employee OR project member | **Match** |
| Unauthorized action | Redirect to home | 403 JSON error | **Different** |

---

## 6. LDAP / Employee Detection

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| LDAP library | Devise LDAP | ldap3 | Different lib |
| Employee check | `FGCZ.employee?(login)` | `_check_is_employee()` | **ASSUMPTION** |
| Projects fetch | `FGCZ.get_user_projects2(login)` | `_get_user_projects()` | **ASSUMPTION** |
| Group pattern | Unknown (in FGCZ gem) | `cn=employees`, `project_XXXX` | **ASSUMPTION** |

### Critical LDAP Assumptions in Python:

```python
# Employee check assumes group named "employees"
search_filter=f"(&(cn=employees)(memberUid={username}))"

# Project check assumes groups named "project_XXXX"
if cn.startswith("project_"):
    project_num = int(cn.replace("project_", ""))
```

**ACTION REQUIRED:** Verify actual LDAP group structure matches these assumptions. The Ruby code uses an external `FGCZ` gem that abstracts this - we need to confirm the actual LDAP schema.

---

## 7. File Downloads

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Download route | Same as listing (`/projects/p1234.bam`) | Same as listing (`/files/p1234/file.bam`) | **Match** |
| File detection | Format-based (`.ext` in URL) | Filesystem check (`is_file()`) | Different approach |
| Download handling | Redirect to fgcz-gstore.uzh.ch | Returns `download_url` to fgcz-gstore.uzh.ch | **Match** |
| Path validation | Regex: `/\Ap\d{4,}\/[\w\-\._\/]+\z/` | `validate_path()` | **Match** |

**Response for files:**
```json
{
  "type": "file",
  "name": "sample.bam",
  "path": "p1234/sample.bam",
  "size": "1.2 GB",
  "size_bytes": 1288490188,
  "modified": "2024-03-15T10:30:00+00:00",
  "download_url": "https://fgcz-gstore.uzh.ch/projects/p1234/sample.bam"
}
```

---

## 8. Size Formatting

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Helper | `number_to_human_size()` | `format_size()` | **Match** |
| Output | "1.2 MB", "500 KB" | "1.2 MB", "500 KB" | **Match** |
| Raw bytes available | No | Yes (`size_bytes` field) | Python better |
| Directory size | `"-"` | `"-"` | **Match** |

---

## 9. Caching

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Directory cache | None | LRU with 30s TTL | **Python better** |
| Cache size | - | 256 directories | - |
| Invalidation | - | Time-bucket based | - |

**Python advantage:** Caching reduces filesystem load for frequently accessed directories.

---

## 10. Error Handling

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Missing directory | Empty listing (no error) | Empty listing (no error) | Match |
| Permission denied | Silent skip | Silent skip | Match |
| Invalid path | No validation | ValidationError 400 | **Python better** |
| Path traversal | Not blocked | Blocked (`..` check) | **Python better** |

---

## 11. Configuration

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| GSTORE_DIR | `SushiFabric::GSTORE_DIR` | `settings.GSTORE_DIR` | Match |
| Default value | `/srv/gstore/projects` | `/srv/gstore/projects` | Match |
| Override | Rails config | `.env` file | Match |
| FGCZ check | `hostname =~ /fgcz/` | Not implemented | **GAP** |

---

## 12. Import from gStore (dataset.tsv)

| Aspect | Ruby | Python | Status |
|--------|------|--------|--------|
| Route | `GET /import/*dataset` | None | **GAP** |
| Employee-only button | Yes (in file listing view) | - | **GAP** |
| TSV parsing | CSV library | - | Not implemented |
| B-Fabric registration | Background process | - | Not implemented |

**GAP:** Dataset import from gStore files is not implemented in Python.

---

## Summary: Critical Gaps

### Must Verify

1. **LDAP Group Schema** - Confirm `employees` and `project_XXXX` patterns match actual LDAP

### Should Implement

2. **Dataset Import** - `/import/*dataset` route for TSV import (employee-only)

### Nice to Have

3. **FGCZ Mode Detection** - Hostname-based feature toggling

### Completed

- ~~File Download Endpoint~~ - Returns `download_url` for external redirect
- ~~Default Sort Order~~ - Matches Ruby (mtime desc for project root)
- ~~Human-readable Sizes~~ - `format_size()` implemented server-side

---

## Summary: Improvements in Python

1. **Caching** - LRU cache with TTL (Ruby has none)
2. **Path Validation** - Explicit traversal prevention
3. **Stateless Pagination** - RESTful query params vs session state
4. **Flexible Page Size** - Any value 1-500 vs fixed options
5. **JSON Errors** - Structured error responses vs redirects
6. **JWT Auth** - Stateless authentication vs session-based

---

## LDAP Schema Questions to Resolve

Before production deployment, confirm:

1. What is the actual LDAP group name for employees?
   - Current assumption: `cn=employees`
   - Ruby uses: `FGCZ.employee?(login)` (abstracted)

2. What is the actual LDAP group pattern for projects?
   - Current assumption: `cn=project_XXXX`
   - Ruby uses: `FGCZ.get_user_projects2(login)` (abstracted)

3. Is there a bioinformatician role separate from employee?
   - Ruby has: `FGCZ.get_bioinformatician_users()`
   - Python: Not implemented

4. What LDAP attributes are used?
   - Current: `memberUid`, `cn`, `gidNumber`, `mail`, `uid`
   - Need to verify against actual LDAP schema
