# Ruby SUSHI Dataset Import - Complete Analysis

This document captures the full analysis of the Ruby SUSHI dataset import functionality, including gotchas, edge cases, and lessons learned.

---

## Backwards Compatibility Decision

**Approach:** Dual-read with SQLAlchemy JSON type, no migration script.

The production database contains existing data with Ruby-specific formats:
- `samples.key_value`: Ruby hash strings like `'{"Name"=>"sample1", "Read1"=>"path"}'`
- `datasets.order_ids`, `job_parameters`: Already JSON-compatible strings

**Implementation:**
1. Use SQLAlchemy `JSON` column type for `order_ids` and `job_parameters` - these are already JSON-compatible
2. For `samples.key_value`, implement a dual-format parser that tries JSON first, falls back to Ruby hash parsing
3. All **new** data written as proper JSON
4. **Old** data readable without migration - parser handles both formats transparently
5. No migration script needed - the fallback parser handles legacy data indefinitely

**Removed fields** (not mapped in Python model, ignored by SQLAlchemy):
- `runnable_apps`, `refreshed_apps` - compute on demand instead of caching
- `order_id` (singular) - derive from `order_ids[0]` if needed
- `child` - derive from `parent_id is not None`

---

## Order IDs Logic (B-Fabric Integration)

**IMPORTANT:** Order IDs have complex logic that affects B-Fabric registration.

### How Order IDs are Collected

Order IDs come from the `Order Id [B-Fabric]` column in the TSV:
```tsv
Name    Read1 [File]    Order Id [B-Fabric]
sample1 /path/file1.fq  12345
sample2 /path/file2.fq  12345
sample3 /path/file3.fq  67890
```

The system collects **unique** order IDs across all samples → `order_ids = [12345, 67890]`

### B-Fabric Registration Logic

When registering a dataset with B-Fabric, the order ID determines the registration target:

| Condition | Registration Target | Reason |
|-----------|---------------------|--------|
| Single order ID ≥ 8000 | Order ID (`o12345`) | Modern order system |
| Single order ID < 8000 | Project number (`p1234`) | Legacy order system |
| Multiple order IDs | Project number (`p1234`) | Can't pick one order |
| No order ID | Skip registration | Nothing to register to |
| Child dataset | Include parent's `bfabric_id` | Link to parent |

### Database Storage

```python
# Stored as JSON array in datasets.order_ids
order_ids: [12345, 67890]

# Primary order ID for backwards compatibility
@property
def primary_order_id(self) -> int | None:
    return self.order_ids[0] if self.order_ids else None
```

### Python Implementation Notes

1. **Extract during import:** Parse `Order Id [B-Fabric]` column, collect unique values
2. **Store as list:** Even single order ID stored as `[12345]` for consistency
3. **B-Fabric integration deferred:** Registration logic not yet implemented in Python
4. **Use `primary_order_id`:** For API responses that expect single order ID

---

## Python API Endpoints

### Import Endpoint Structure

```
POST /projects/{project_number}/datasets/import           # Import TSV file
POST /projects/{project_number}/datasets/import/preview   # Preview before import
POST /datasets/validate                                   # Validate TSV (no project needed)
```

| Endpoint | Purpose |
|----------|---------|
| `POST /projects/{pn}/datasets/import` | Full import - creates dataset and samples |
| `POST /projects/{pn}/datasets/import/preview` | Preview - parses TSV, checks duplicates, no DB writes |
| `POST /datasets/validate` | Validate TSV structure only (no project context needed) |

**Design decision:** Import operations are under `/projects/{pn}/` because datasets always belong to a project. The validate endpoint is under `/datasets/` because it only checks TSV structure without needing project context.

---

## 1. Routes & Entry Points

### Two Import Paths

| Route | Method | Purpose |
|-------|--------|---------|
| `POST /data_set/import` | `DataSetController#import` | Web form file upload |
| `GET /import/*dataset` | `DataSetController#import_from_gstore` | Import from GStore filesystem |

**Source files:**
- Routes: `/config/routes.rb` (lines 59, 116)
- Controller: `/app/controllers/data_set_controller.rb`
  - `import()`: lines 626-767
  - `import_from_gstore()`: lines 481-590

---

## 2. TSV Format Specification

### Standard Single-Dataset TSV

```tsv
DataSetName	MyAnalysisResults
ProjectNumber	1234
ParentID	5678
Comment	Optional description
Name	Read1 [File]	Read2 [File]	Species	Order Id [B-Fabric]
sample1	p1234/sample1_R1.fastq.gz	p1234/sample1_R2.fastq.gz	human	12345
sample2	p1234/sample2_R1.fastq.gz	p1234/sample2_R2.fastq.gz	mouse	12345
```

### Multi-Dataset TSV Format

Multiple datasets separated by blank rows:

```tsv
DataSetName	Dataset1
ProjectNumber	1234

Name	Read1 [File]	Species
sample1	p1234/s1.fq	human

DataSetName	Dataset2
ProjectNumber	1234

Name	Read1 [File]	Species
sample2	p1234/s2.fq	mouse
```

### Special Column Tags

| Tag | Purpose | Example |
|-----|---------|---------|
| `[File]` | File reference in GStore | `Read1 [File]` |
| `[Link]` | URL reference | `Report [Link]` |
| `[Factor]` | Experimental factor | `Condition [Factor]` |
| `[B-Fabric]` | B-Fabric reference | `Sample Id [B-Fabric]` |

### Metadata Rows (Optional)

| Key | Required | Description |
|-----|----------|-------------|
| `DataSetName` | Yes | Name of the dataset |
| `ProjectNumber` | Yes | Project number (e.g., 1234) |
| `ParentID` | No | Parent dataset ID for child datasets |
| `Comment` | No | Dataset description |

---

## 3. Parsing Implementation

### Ruby CSV Parsing

```ruby
data_set_tsv = CSV.readlines(tsv.path, :headers => true, :col_sep => "\t")
headers = data_set_tsv.headers
```

### Multi-Dataset Detection

```ruby
# First pass: scan for "ProjectNumber" to detect multi-dataset format
first_line = true
open(tsv) do |input|
  while line = input.gets
    if first_line and line =~ /ProjectNumber/
      # Multi-dataset format detected
    end
  end
end
```

### Row Processing

```ruby
rows = []
data_set_tsv.each do |row|
  unless row.fields.join.strip.empty?  # Skip empty rows
    rows << row.fields
  end
end
```

---

## 4. Validation Checks

### Blank Column Check (GOTCHA)

```ruby
unless headers.include?(nil)
  @data_set_id = DataSet.save_dataset_to_database(...)
else
  session['import_fail'] = 'There must be a blank column. Please check it.'
end
```

**Note:** This checks if headers contain `nil` (blank column). The error message is confusing - it appears to REQUIRE a blank column, possibly for TSV delimiter handling.

### Sample Name Validation

```ruby
if header == 'Name' and file =~ /[!@\#$%^&*\(\)\<\>\{\}\[\]\/:; '"=+\|]/
  @sample_invalid_name[file] = true
end
```

Only flags invalid names - doesn't prevent import.

### Order ID Extraction

```ruby
if header == 'Order Id [B-Fabric]'
  order_ids[cell] = true  # Collect unique order IDs
end
```

---

## 5. Database Operations

### Save Flow

```ruby
# 1. Find or create Project
project = Project.find_by_number(project_number.to_i)
unless project
  project = Project.new
  project.number = project_number.to_i
  project.save
end

# 2. Create DataSet
data_set = DataSet.new
data_set.name = data_set_hash['DataSetName']
data_set.project = project
data_set.user = user
data_set.save

# 3. Create Samples (one per row)
rows.each do |row|
  sample_hash = {}
  headers.each_with_index do |header, i|
    sample_hash[header] = row[i]
  end
  sample = Sample.new
  sample.key_value = sample_hash.to_s  # CRITICAL: Stored as Ruby hash string
  sample.save
  data_set.samples << sample
end
```

### Sample Storage (SECURITY ISSUE)

```ruby
# Storage
sample.key_value = sample_hash.to_s  # {"Name"=>"sample1", "Read1"=>"..."}

# Retrieval (in Sample#to_hash)
def to_hash
  eval(self.key_value)  # DANGEROUS: eval on stored data
end
```

### Database Schema

**DataSet table:**
- `id`, `project_id`, `parent_id`, `name`, `md5`, `comment`
- `user_id`, `child` (boolean)
- `bfabric_id`, `workunit_id`
- `order_ids` (serialized Array)
- `job_parameters` (serialized Hash)
- `app_name`, `run_name_order_id`
- `num_samples`, `completed_samples`, `refreshed_apps`, `runnable_apps`
- `created_at`, `updated_at`

**Sample table:**
- `id`, `data_set_id`, `key_value` (text), `created_at`, `updated_at`

---

## 6. B-Fabric Integration

### Registration Trigger

```ruby
# After successful import (double-fork to avoid zombies)
unless session[:off_bfabric_registration]
  pid = Process.fork do
    Process.fork do
      data_set.register_bfabric
    end
  end
  Process.waitpid pid
end
```

### Pre-Registration Checks

```ruby
# Must have [File] tag column
unless has_file_tag_column?
  warn "Not registering: no [File] tag column"
  return false
end

# Headers must be unique (ignoring tags)
if duplicate_headers_ignoring_tags.any?
  warn "Not registering: duplicate column names"
  return false
end
```

### Registration Command

```ruby
register_command = "register_sushi_dataset_into_bfabric"

# Order ID > 8000: use order ID
# Order ID <= 8000: use project number
# Child dataset: include parent bfabric_id
# Multi-order: use project number

command = [
  register_command,
  "o#{order_id}",  # or "p#{project_number}"
  dataset_tsv_path,
  dataset_name,
  dataset_id,
  "--skip-file-check"
].join(" ")
```

---

## 7. Error Handling

| Scenario | Ruby Behavior | Problem |
|----------|--------------|---------|
| File not found | Silent failure | No error message |
| CSV parse error | Raises exception | Crashes request |
| Blank column in headers | Sets session warning | Confusing message |
| Duplicate dataset (MD5) | Warning after import | Doesn't prevent |
| Sample eval fails | Warns, continues | Data loss |
| B-Fabric command fails | Warns, returns false | Silent failure |
| Missing order ID | Skips registration | No notification |

### No Transaction Management

Samples are saved one by one. If parsing fails mid-way, partial data remains in database.

---

## 8. Access Control

### Current (Flawed) Implementation

```ruby
# Only checks session[:project] exists
# Does NOT verify user has access to target project
if session[:project]
  # Allow import
end
```

### Employee Check (Not Used for Import)

```ruby
def employee?
  SushiFabric::Application.config.fgcz? and
    current_user and
    FGCZ.employee?(current_user.login)
end
```

---

## 9. Edge Cases & Gotchas

### 1. Multi-Dataset TSV Bug

```ruby
data_set_arr.each do |data_set|
  @data_set_id = DataSet.save_dataset_to_database(...)
end
# Only returns LAST @data_set_id - others are lost
```

### 2. Path Traversal Risk

```ruby
tsv = File.join(GSTORE_DIR, "#{params[:dataset]}.#{params[:format]}")
# params[:dataset] is not sanitized - could contain ../
```

### 3. Plate/Meta-Dataset Feature

```ruby
# Splits input into plate datasets
# Creates parent with: ["Name", "Species", "CellDataset [File]"]
# Naming: Plate_001, Plate_002, etc.
digit = ((Math.log10(plates.length)*10).to_i/10)+1
```

### 4. Order ID Complexity

- Single order ID < 8000: Use project number for B-Fabric
- Single order ID >= 8000: Use order ID for B-Fabric
- Multiple order IDs: Use project number
- Child dataset: Include parent's bfabric_id

### 5. File Path Construction

```ruby
# Extract dataset path from first file
@sample_path = file_list.map { |f| File.dirname(f) }.uniq
@dataset_path = @sample_path.map { |p| p.split('/')[0,2].join('/') }
# Takes first 2 path segments: p1234/DatasetName
```

### 6. MD5 Duplicate Detection

```ruby
def md5hexdigest
  key_value = samples.map { |s| s.key_value }.join +
              parent_id.to_s +
              project_id.to_s
  Digest::MD5.hexdigest(key_value)
end
```

Only warns after import - doesn't prevent duplicates.

### 7. CSV Dialect Issues

- Only `:col_sep => "\t"` specified
- No quote character handling
- No encoding specification
- No line ending handling

---

## 10. Related Features

### Merge Datasets

```ruby
def merge_with(other_dataset, options: {})
  # Joins two datasets on matching column (default: "Name")
  # Handles Read1/Read2 concatenation
  # Sums Read Count columns
  # Excludes "Sample Id [B-Fabric]" by default
  # Creates child dataset with app_name = "MergeReadDatasets"
end
```

### Delete Operations

| Method | Action |
|--------|--------|
| `destroy` | Full deletion with GStore cleanup |
| `run_delete_only_data_files` | Remove files, keep metadata |

---

## 11. Historical Evolution

### Evolution Indicators

1. **Multi-dataset support** - Added later (two code paths in import_from_gstore)
2. **Plate/meta-dataset** - Optional feature via params
3. **Order ID tracking** - Retrofitted (uses serialized array)
4. **B-Fabric registration** - Evolved to use grandchild process
5. **Tag system** - Added to headers (String#tag? method)

### Commented-Out Code

```ruby
#when /html$/
#  send_file file_full_path, disposition: 'inline', type: 'text/html'
```

Suggests HTML handling was removed/changed.

---

## 12. Key Lessons for Python Implementation

1. **Use JSON, not eval** - Store sample data as JSON, not eval-able strings
2. **Validate paths** - Prevent path traversal attacks
3. **Use transactions** - All-or-nothing imports
4. **Check access first** - Verify project access before any database operations
5. **Handle multi-dataset** - Return all created IDs, not just last
6. **Pre-check duplicates** - Option to reject before saving
7. **Proper CSV handling** - Specify encoding, quote chars, error handling
8. **Clear error messages** - Don't confuse users with "blank column" errors
9. **Skip B-Fabric initially** - Implement as separate integration later
10. **Log properly** - Use structured logging, not stderr warns

---

# Python Implementation Plan

## Core Data Flow

```
Input Dataset (parent) → Run App → Output Dataset (child)
                              ↓
                           Job record links them
```

---

## Beat 1: Sample Storage Migration Strategy

**Current state:** `samples.key_value` stores Ruby hash strings
```
'{"Name"=>"sample1", "Read1 [File]"=>"p1234/file.fq"}'
```

**Target state:** JSON format
```json
{"Name": "sample1", "Read1 [File]": "p1234/file.fq"}
```

**Approach:** Dual-read, single-write
- Write new samples as JSON only
- Read function detects format and parses accordingly
- Migration script converts existing data (one-time)

```python
def parse_sample_data(key_value: str) -> dict:
    """Parse sample data from either JSON or Ruby hash format."""
    try:
        return json.loads(key_value)  # Try JSON first
    except json.JSONDecodeError:
        return parse_ruby_hash(key_value)  # Fallback to Ruby format

def parse_ruby_hash(s: str) -> dict:
    """Convert Ruby hash string to Python dict.
    '{"Name"=>"value"}' → {"Name": "value"}
    """
    # Replace Ruby => with JSON :
    # Handle edge cases (nested, escaped quotes)
```

**Migration script:** Separate CLI command to convert all existing samples

---

## Beat 2: Update DataSet Model

Add missing fields to match actual database schema:

```python
class DataSet(SQLModel, table=True):
    # Existing fields...

    # Add these:
    runnable_apps: str | None = None       # Cached list of runnable apps
    refreshed_apps: bool | None = None     # Whether apps list is fresh
    run_name_order_id: str | None = None   # For ManGO integration
    workunit_id: int | None = None         # B-Fabric workunit
    order_ids: str | None = None           # Serialized list of order IDs
    job_parameters: str | None = None      # Serialized job params
```

---

## Beat 3: Web Upload Endpoint

**Endpoint:** `POST /datasets/import/upload`

**Request:** Multipart form with TSV file

**Flow:**
1. Receive file upload
2. Validate file size (configurable limit)
3. Parse TSV in memory
4. Validate content (headers, required fields)
5. Check project access
6. Check for duplicates (MD5)
7. Save in transaction
8. Return created dataset(s)

**Key considerations:**
- File size limit (100MB default)
- Memory-efficient parsing (stream if huge)
- Clear error messages with line numbers
- Support both single and multi-dataset TSVs

---

## Beat 4: TSV Parser

**Responsibilities:**
- Detect metadata rows (DataSetName, ProjectNumber, etc.)
- Detect multi-dataset format
- Parse column headers and tags
- Validate required fields
- Handle encoding (UTF-8 with fallback)
- Handle edge cases (empty rows, trailing tabs)

**Output:** List of `ParsedDataset` objects ready for database insertion

---

## Beat 5: Validation Layer

**Path/File validation:**
- File exists and is readable
- File size within limits
- File extension is .tsv or .txt

**TSV content validation:**
- Has DataSetName
- Has ProjectNumber (valid integer)
- Has header row with at least Name column
- Has at least one data row
- No duplicate column names
- Row lengths match header count

**Access validation:**
- User has access to target project(s)
- Or user is employee

**Duplicate validation:**
- Compute MD5 of content
- Check against existing datasets
- Option to allow or reject duplicates

---

## Beat 6: Database Transaction

**All-or-nothing saves:**
```python
with transaction():
    project = get_or_create_project(project_number)
    dataset = create_dataset(...)
    for row in rows:
        create_sample(dataset_id=dataset.id, data=row)
    # Commit all together
```

**If any step fails:** Roll back everything, return clear error

---

## Beat 7: Response Format

**Success:**
```json
{
  "success": true,
  "datasets": [
    {
      "id": 123,
      "name": "MyDataset",
      "project_number": 1234,
      "sample_count": 50
    }
  ]
}
```

**Validation error:**
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Missing required column: Name",
    "line": 5
  }
}
```

**Duplicate warning:**
```json
{
  "success": true,
  "datasets": [...],
  "warnings": ["Similar dataset exists (ID: 456)"]
}
```

---

## Beat 8: GStore Import (Mock for Now)

**Endpoint:** `POST /datasets/import/gstore`

**Initial implementation:**
- Accept path parameter
- Validate path format
- Return mock success response
- TODO comment for real implementation

**Later:** Read actual file from GSTORE_DIR, use same parser as web upload

---

## Things to Keep in Mind

1. **Column tags are metadata** - `[File]`, `[Link]`, `[Factor]` affect how apps interpret columns, not how we store them

2. **Parent-child relationship** - Datasets form a tree. Root datasets have `parent_id=null`. App outputs have `parent_id` set.

3. **MD5 includes context** - Hash computed from samples + parent_id + project_id to catch true duplicates

4. **Project auto-creation** - If project doesn't exist, create it (employees only? or always?)

5. **Order IDs for B-Fabric** - Extract from `Order Id [B-Fabric]` column, store for future B-Fabric integration

6. **app_name** - Set when dataset is created by an app, null for imported root datasets

7. **No file existence check** - We don't verify that `[File]` paths actually exist on GStore (Ruby uses `--skip-file-check`)

8. **Samples are denormalized** - Each sample stores full key-value data, not normalized columns

---

## Implementation Order

1. ✅ **Update DataSet model** - Add missing fields (`app/models.py`)
2. ✅ **Create sample parser utility** - Dual-format reader (`app/utils/sample_parser.py`)
3. ✅ **Create TSV parser** - Extract metadata, headers, rows (`app/utils/tsv_parser.py`)
4. ✅ **Create import service** - Orchestrates validation and saving (`app/services/dataset_import.py`)
5. ✅ **Create upload endpoint** - Multipart form handling (`app/api/routes/datasets.py`)
6. ⏳ **Create mock GStore endpoint** - Placeholder (deferred - web upload prioritized)
7. ⏳ **Add migration script** - Not needed (dual-read parser handles legacy data)
8. ⏳ **Tests** - Parser, validation, service, endpoint
