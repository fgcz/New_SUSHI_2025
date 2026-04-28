# Running Applications - Input Schema
**Last Updated:** 2026-04-28

This document explains the application input schema structure and how it's handled in the frontend.

## Overview

When a user runs an application on a dataset, the frontend needs to know:
1. What parameters the application accepts
2. How to group and display those parameters
3. What types and defaults each parameter has

## Example Response

```json
{
  "application": {
    "name": "CountQC",
    "class_name": "CountQC",
    "category": "QC",
    "description": "Quality control analysis for count data",
    "required_columns": ["Name", "Count"],
    "required_params": ["cores", "ram"],
    "modules": ["Tools/QC"],
    "param_groups": [
      {
        "id": "resources",
        "title": "Resource Parameters",
        "description": "Configure compute resources for the job",
        "fields": [
          { "name": "cores", "type": "integer", "default_value": 8, "description": "Number of CPU cores" },
          { "name": "ram", "type": "integer", "default_value": 32, "description": "RAM in GB" },
          { "name": "scratch", "type": "integer", "default_value": 400, "description": "Scratch space in GB" },
          { "name": "partition", "type": "select", "default_value": "normal", "options": ["normal", "high", "low"], "description": "Cluster partition" }
        ]
      },
      {
        "id": "analysis",
        "title": "Tool Parameters",
        "description": "Configure analysis parameters",
        "fields": [
          { "name": "ref", "type": "select", "default_value": "hg38", "options": ["hg38", "hg19", "mm10", "mm39"], "description": "Reference genome" },
          { "name": "paired", "type": "boolean", "default_value": true, "description": "Paired-end data" }
        ]
      }
    ]
  }
}
```

## Frontend Implementation

### Multi-Step Form

The frontend renders parameter groups as a multi-step wizard:

1. **URL-based Navigation**: Steps are tracked via URL query params (`?step=1`, `?step=2`)
2. **FormStepper Component**: Visual progress indicator showing current step
3. **StepNavigation Component**: Back/Next buttons for navigation

### Key Files

| File | Purpose |
|------|---------|
| `lib/types/app-form.ts` | TypeScript interfaces for the schema |
| `lib/api/applications.ts` | API calls to fetch form schema |
| `lib/hooks/application/useApplicationForm.ts` | Form state management hook |
| `lib/utils/form-renderer.tsx` | Field rendering utilities |
| `app/.../run-application/[appName]/page.tsx` | Main form page |
| `app/.../run-application/[appName]/FormStepper.tsx` | Step progress indicator |
| `app/.../run-application/[appName]/StepNavigation.tsx` | Navigation buttons |

### Field Type Rendering

The `FormFieldComponent` in `form-renderer.tsx` handles each field type:

- `text`: Standard text input
- `integer`: Number input with step=1
- `float`/`number`: Number input with step=any
- `select`: Dropdown with options
- `multi_select`: Multi-select dropdown
- `boolean`: Checkbox with inline label
- `section`: Section header (non-input)

### Field Validation

The form supports dynamic validation where field changes trigger a backend request to get an updated schema. This is useful for limiting dropdown options based on other field values.

When a user changes a field and leaves it (on blur), the frontend sends the current form values to:

```
POST /api/v1/application_configs/{appName}/validate
Body: { config: { cores: 8, ram: 32, ref: "hg38", ... } }
```

The backend responds with an updated `AppFormResponse`. The frontend then:
1. Updates the field configurations (new options, disabled states, etc.)
2. Updates form values with any new defaults from the response

This enables scenarios like:
- Selecting a reference genome filters available annotation options
- Choosing a partition updates the maximum allowed cores/RAM
- Enabling a feature reveals additional related parameters

---

## Submission Pipeline

### Overview

The job submission follows a multi-page flow with state persistence:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Run Application │────▶│  Confirm/Review │────▶│   Job Running   │
│  (Multi-step)    │◀────│                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
      Fill form          Review & Submit         Success redirect
```

### State Persistence

Form data is stored in `sessionStorage` to survive navigation between the form and review pages.

**Storage Key:** `sushi_job_submission_data`

**Stored Data Structure:**
```typescript
{
  projectNumber: number;
  datasetId: number;
  appName: string;
  nextDataset: {
    name: string;
    comment?: string;
  };
  parameters: Record<string, any>;
}
```

### When State is Saved

Data is saved to `sessionStorage` when the user clicks "Review" (submits the form to go to the confirm page).

**Location:** `run-application/[appName]/page.tsx` in `handleSubmit()`

### When State is Restored

Data is restored from `sessionStorage` when:
1. User navigates back from the Confirm page to edit parameters
2. The `useApplicationForm` hook checks for matching stored data on mount

**Location:** `lib/hooks/application/useApplicationForm.ts`

The hook only restores data if `appName` and `datasetId` match the stored values. This prevents loading stale data from a different app or dataset.

### When State is Cleared

| Event | Cleared? | Location |
|-------|----------|----------|
| Successful job submission | Yes | `confirm/page.tsx` in `submitSuccess` effect |
| Mock run | Yes | `confirm/page.tsx` in `handleMockRun()` |
| Browser tab closed | Yes | Automatic (sessionStorage behavior) |
| User navigates away | No | Data persists for potential return |
| Different app/dataset | Ignored | Matching check fails, defaults used |

### Why sessionStorage?

We use `sessionStorage` instead of `localStorage` because:

1. **Auto-cleanup**: Data clears when the tab closes, preventing stale submissions
2. **Tab isolation**: Each tab has its own storage, allowing parallel submissions
3. **User expectation**: Closing a tab signals intent to abandon the form
4. **No manual expiry**: No need to track timestamps or implement TTL logic

### User Flow Examples

**Happy Path:**
1. User fills form across multiple steps
2. Clicks "Review" → data saved to sessionStorage → navigates to confirm page
3. Reviews parameters, clicks "Submit"
4. Job submitted → sessionStorage cleared → redirects to dataset page

**Edit Flow:**
1. User fills form, clicks "Review"
2. On confirm page, notices a mistake
3. Clicks "Back to Edit" → returns to form
4. Form restores values from sessionStorage
5. User edits, clicks "Review" again → updated data saved
6. Submits successfully

**Abandon Flow:**
1. User fills form partially
2. Closes browser tab
3. sessionStorage automatically cleared
4. Next visit starts fresh

### Key Files

| File | Role in Pipeline |
|------|------------------|
| `run-application/[appName]/page.tsx` | Saves data on "Review" click |
| `run-application/[appName]/confirm/page.tsx` | Loads data, clears on submit |
| `lib/hooks/application/useApplicationForm.ts` | Restores data on back navigation |

### NextDataset Section

The form includes a "NextDataset" section (above the parameter steps) where users specify:
- **Name**: Output dataset name (auto-generated default: `{appName}_{datasetName}_{date}`)
- **Comment**: Optional description

This section is always visible regardless of which step the user is on, since it applies to the entire submission rather than a specific parameter group.
