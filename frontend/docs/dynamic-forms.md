# Dynamic Form System Implementation (Run Application)

## Overview

The dynamic form system enables the frontend to generate forms dynamically based on API definition. This allows different applications (cellRanger, Seurat, scanpy, etc.) to define their own input parameters without requiring frontend code changes.

### Field Types Supported

- **text**: Basic string input
- **number**: Numeric input with min/max validation
- **select**: Dropdown with predefined options
- **textarea**: Multi-line text input

### Core Components

1. **Type Definitions** (`lib/types/app-form.ts`)
2. **API Layer** (`lib/api/applications.ts`)
3. **Form Renderer** (`lib/utils/form-renderer.tsx`)
4. **Dynamic Page** (`app/projects/[projectNumber]/datasets/[datasetId]/run-application/[appName]/page.tsx`)

## Type System

### `AppFormResponse` - API Response

```typescript
export interface AppFormResponse {
  appName: string;
  description: string;        
  fields: AppFormField[];
}

export interface AppFormField {
  name: string;                              // Unique field identifier
  type: 'text' | 'number' | 'select' | 'textarea';
  label: string;
  options?: string[];                        // For select fields
  default?: any;
  min?: number;                              // For number fields
  max?: number;                              // For number fields
  required?: boolean;
  placeholder?: string;
}
```

### `JobSubmissionRequest` - Form Submission

```typescript
export interface JobSubmissionRequest {
  project_number: number;
  dataset_id: number;
  app_name: string;
  next_dataset: {
    name: string;
    comment?: string;
  };
  parameters: DynamicFormData; // All form field values
}

export interface DynamicFormData {
  [fieldName: string]: any;
}
```

## Mock API Implementation

```typescript
// GET /api/applications/cellRanger/form
{
  "appName": "cellRanger",
  "fields": [
    {
      "name": "cores",
      "type": "select",
      "label": "CPU Cores",
      "options": ["4", "8", "16", "32"],
      "default": "8",
      "required": true
    },
    {
      "name": "expectedCells",
      "type": "number",
      "label": "Expected Number of Cells",
      "min": 500,
      "max": 50000,
      "default": 3000,
      "required": true
    },
    // ... more fields
  ]
}
```

## Form Renderer Implementation

The form renderer consists of two main functions:

- **`renderFormField(field, value, onChange)`**: Returns a single field component JSX (`<input>` or `<select>`)
- **`FormFieldComponent(field, value, onChange)`**: Wraps the field in a div with proper labels

## Page Implementation

The dynamic form page follows this flow:

1. **Data Fetching**: 
   - Uses `useQuery` with `projectApi.getProjectDatasets()` → `projectData, isProjectLoading, projectError`
   - Uses `useQuery` with `applicationApi.getFormSchema(appName)` → `formConfig, isFormConfigLoading, formConfigError`

2. **State Management**: 
   - `nextDatasetData` state manages next dataset name and comment fields
   - `dynamicFormData` state saves the current dynamic form values and updates accordingly

3. **Form Submission**: Creates `JobSubmissionRequest` object and handles submission with proper validation and error handling


## Testing Strategy

### Unit Tests
- Field renderer for each input type
- Form initialization with default values
- State management for field changes
- Validation logic for required fields

### Integration Tests

- API response handling
- Form submission flow
- Error state management
- Loading state behavior

### E2E Tests

- Complete form filling workflow
- Navigation between different apps
- Job submission success/failure scenarios
