# Omics Apps

Apps define **what** to compute. The service layer handles **how** to run it.

## Structure

```
omics_apps/
├── __init__.py      # Registry: get_app(), list_apps()
├── base.py          # MultiOmicsApp base class
├── config.py        # Constants (paths, defaults)
├── r_heredoc.py     # R script generation for ezRun apps
├── fastqc.py        # FastQC app
└── countqc.py       # CountQC app

app/
├── api/serializers/omics_app.py   # Convert app → frontend JSON
└── services/
    ├── job_submission.py      # Orchestrates submission
    └── slurm_service.py       # Script building + SLURM
```

## Public API

```python
from omics_apps import get_app, list_apps, get_runnable_apps

list_apps()                  # ["FastQC", "CountQC", ...]
get_app("FastQC")            # App instance for execution
get_runnable_apps(headers)   # Apps matching dataset headers
```

For frontend config:
```python
from omics_apps import get_app
from app.api.serializers.omics_app import serialize_app_config

app = get_app("FastQC")
config = serialize_app_config(app)  # Config dict for frontend form
```

For filtering apps by dataset:
```python
from omics_apps import get_runnable_apps

headers = ["Name", "Read1 [File]", "Read2 [File]"]
apps = get_runnable_apps(headers)
# [{"category": "QC", "apps": [{"class_name": "FastQC", "description": "..."}]}]
```

## No Database for App Definitions

Unlike the original Ruby SUSHI which stored app metadata in a `sushi_applications` database table for caching, the Python backend uses an **in-memory registry** exclusively. The database table existed in Ruby to avoid repeatedly loading 100+ app files on each request.

In Python, this caching layer is unnecessary because:
- All apps are imported once at startup via `importlib`
- Class attributes (name, category, required_columns) are accessed directly - no instantiation needed
- Filtering 200 apps in memory takes ~0.1ms vs ~5ms for a database query

This simplifies the architecture: app definitions live only in code, with no sync mechanism needed between files and database.

## App Definition

Each app inherits from `MultiOmicsApp` and defines:

| Attribute/Method | Required | Description |
|------------------|----------|-------------|
| `name` | Yes | Display name (registry key) |
| `category` | Yes | Grouping (QC, Alignment, etc.) |
| `description` | No | Help text |
| `required_columns` | Yes | Columns input dataset must have |
| `modules` | No | HPC modules to load |
| `param_groups` | Yes | Parameter group definitions |
| `params_definition` | Yes | Parameter definitions with metadata |
| `commands()` | Yes | Shell commands to execute |
| `next_dataset()` | Yes | Output file specification |
| `set_default_parameters()` | No | Set defaults based on dataset |
| `adjust_requirements()` | No | Adjust required_columns/modules based on params |
| `adjust_params()` | No | Dynamic form updates based on user input |
| `grandchild_datasets()` | No | Additional output datasets |

## Lifecycle Hooks

Apps have two optional hooks that run before validation:

```
configure()
    ↓
set_default_parameters()   ← Hook 1: detect from data → set params
    ↓
adjust_requirements()      ← Hook 2: use params → adjust requirements
    ↓
validation
    ↓
commands() / next_dataset()
```

### Why Two Separate Hooks?

They have opposite data flows:

| Hook | Input | Output |
|------|-------|--------|
| `set_default_parameters()` | dataset columns | param values |
| `adjust_requirements()` | param values | required_columns, modules |

### Example: How `adjust_requirements()` Prevents Crashes

FastQC can run in single-end or paired-end mode. In paired mode, it needs the Read2 column.

```python
class FastQCApp(MultiOmicsApp):
    required_columns = ["Name", "Read1"]  # Read2 not required by default

    def set_default_parameters(self):
        # Auto-detect: if Read2 exists, enable paired mode
        if self.dataset_has_column("Read2"):
            self.params["paired"] = True

    def adjust_requirements(self):
        # If paired mode, require Read2 column
        if self.params.get("paired"):
            self.required_columns = [*self.required_columns, "Read2"]
```

**Scenario: User manually enables paired mode on single-end data**

Without `adjust_requirements()`:
1. User sets `paired=True` on dataset with only Read1
2. Validation passes (Read2 not in required_columns)
3. Job starts, R script crashes: "Read2 column not found"
4. User wasted time waiting for job to fail

With `adjust_requirements()`:
1. User sets `paired=True`
2. `adjust_requirements()` adds Read2 to required_columns
3. Validation fails immediately: "Missing required column: Read2"
4. User sees clear error before job starts

## Dynamic Forms with `adjust_params()`

Apps can implement dynamic form behavior where changing one field affects others. The frontend calls `POST /applications/{app_name}/validate` on field blur, and apps can override `adjust_params()` to return a modified parameter schema.

```python
def adjust_params(self, current_values: dict) -> list[dict]:
    """Called when user changes a form field. Return updated params_definition."""
    import copy
    params = copy.deepcopy(self.params_definition)

    # Example: show GTF file field only when custom genome is selected
    if current_values.get("genome") == "custom":
        for p in params:
            if p["name"] == "gtf_file":
                p["hidden"] = False

    return params
```

Use cases:
- Show/hide fields based on other field values
- Change dropdown options dynamically
- Update default values based on selections
- Validate field combinations

By default, `adjust_params()` returns `params_definition` unchanged (no dynamic behavior).

## The Output Contract

`next_dataset()` defines a **contract** between Python and the R script.

```python
def next_dataset(self) -> dict:
    return {
        "Name": "FastQC",
        "Report [Link]": f"{self.result_dir}/report.html",
        "Data [File]": f"{self.result_dir}/data/",
    }
```

This dict specifies:
1. **Column names** for the output dataset
2. **Expected file paths** where outputs will be created

### How the Contract Works

```
┌─────────────────────────────────────────────────────────────────┐
│ Python (next_dataset)                                           │
│                                                                 │
│ "I expect these files:"                                         │
│   - /srv/gstore/p1001/FastQC_2024/report.html                  │
│   - /srv/gstore/p1001/FastQC_2024/data/                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ R Script (EzAppFastqc)                                          │
│                                                                 │
│ Receives paths via output list:                                 │
│   output[['Report [Link]']] = '/srv/gstore/.../report.html'    │
│   output[['Data [File]']] = '/srv/gstore/.../data/'            │
│                                                                 │
│ Creates files at exactly those paths                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ MultiOmicsStudio (after job completes)                                     │
│                                                                 │
│ 1. Checks files exist at expected paths                         │
│ 2. Registers output dataset with columns from next_dataset()    │
│ 3. Links files in the UI                                        │
└─────────────────────────────────────────────────────────────────┘
```

### Contract Rules

1. **Python decides the paths** - The app defines where outputs go
2. **R must respect the paths** - R script writes to exactly those locations
3. **Column tags matter**:
   - `[Link]` - Clickable link in UI (HTML reports)
   - `[File]` - Downloadable file/directory

## Parameter Definition

Each parameter in `params_definition` is a dict:

```python
{
    "name": "cores",           # Required: parameter key
    "type": "select",          # Required: integer, text, boolean, select
    "default": 8,              # Required: default value
    "group": "resources",      # Required: which param_group
    "description": "CPU cores", # Optional: help text
    "options": [1, 2, 4, 8],   # Required for select type
    "required": True,          # Optional: must be provided
    "placeholder": "...",      # Optional: input placeholder
    "min": 1,                  # Optional: numeric min
    "max": 100,                # Optional: numeric max
}
```

### Types

| Type | Renders as | Needs `options` |
|------|------------|-----------------|
| `integer` | Number input | No |
| `text` | Text input | No |
| `boolean` | Checkbox | No |
| `select` | Dropdown | Yes |

## Example App

```python
from omics_apps.base import MultiOmicsApp
from omics_apps.r_heredoc import generate_r_heredoc

class FastQCApp(MultiOmicsApp):
    name = "FastQC"
    category = "QC"
    description = "Quality control for sequencing data"
    required_columns = ["Name", "Read1"]
    modules = ["QC/FastQC", "Dev/R"]

    param_groups = [
        {"id": "resources", "title": "Resource Parameters"},
        {"id": "analysis", "title": "Analysis Parameters"},
    ]

    params_definition = [
        {"name": "cores", "type": "select", "default": 8,
         "options": [1, 2, 4, 8], "group": "resources", "required": True},
        {"name": "paired", "type": "boolean", "default": False, "group": "analysis"},
    ]

    def set_default_parameters(self) -> None:
        if self.dataset_has_column("Read2"):
            self.params["paired"] = True

    def adjust_requirements(self) -> None:
        if self.params.get("paired"):
            self.required_columns = [*self.required_columns, "Read2"]

    def commands(self) -> str:
        return generate_r_heredoc(self, app_name="EzAppFastqc")

    def next_dataset(self) -> dict:
        return {
            "Name": "FastQC",
            "Report [Link]": f"{self.result_dir}/report.html",
        }
```

## Adding a New App

Create a file in `omics_apps/` - it's auto-discovered:

```python
# omics_apps/star.py
from omics_apps.base import MultiOmicsApp
from omics_apps.r_heredoc import generate_r_heredoc

class STARApp(MultiOmicsApp):
    name = "STAR"
    category = "Alignment"
    # ... define params, commands, next_dataset
```

Auto-discovery imports all `.py` files except those listed in `_EXCLUDED` in `__init__.py`. If you add a new utility module (e.g., a heredoc generator), add its name to `_EXCLUDED` to prevent it from being scanned as an app module.

**Startup-time registration:** The app registry is built once when the `omics_apps` module is first imported (typically at server startup). Python caches imported modules, so subsequent imports return the cached registry without re-scanning. This means adding a new app file requires a server restart to be discovered.

**Abstract intermediate base classes:** Only subclasses with a `name` attribute are registered. Omitting `name` allows you to create shared base classes that aren't exposed as apps:

```python
class RBaseApp(MultiOmicsApp):
    """Base for all R apps - no name, not registered."""
    modules = ["Dev/R"]

class FastQCApp(RBaseApp):
    name = "FastQC"  # This one gets registered
```

## Submission Flow

```
Route receives submit request
    │
    ▼
JobSubmissionService.submit()
    ├── get_app(app_name)
    ├── Load dataset and samples
    ├── Configure app (params, paths)
    ├── app.set_default_parameters()
    ├── app.adjust_requirements()
    ├── Validate columns and params
    ├── Generate script via slurm_service
    ├── Create output dataset in DB
    ├── Create job record in DB
    ├── Write script to disk
    └── Submit to SLURM
    │
    ▼
Return {job_id, status}
```
