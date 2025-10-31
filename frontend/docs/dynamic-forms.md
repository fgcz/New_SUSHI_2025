# Dynamic Form System Implementation (Run Application)

## Overview

The dynamic form system generates forms dynamically based on SUSHI Application Ruby files parsed by the backend. This allows different applications (cellRanger, Seurat, scanpy, etc.) to define their own input parameters in their Ruby app definitions without requiring frontend code changes.

### Field Types Supported

- **text**: Basic string input
- **integer**: Integer numeric input with step=1
- **float**: Floating point numeric input with step=any
- **number**: General numeric input (legacy)
- **select**: Single-selection dropdown with predefined options
- **multi_select**: Multiple-selection dropdown
- **boolean**: Checkbox input for true/false values
- **section**: Section headers and dividers for form organization

### Core Components

1. **Type Definitions** (`lib/types/app-form.ts`)
2. **Backend Parser** (`backend/app/services/application_config_parser.rb`)
3. **API Layer** (`lib/api/applications.ts`) - calls `/api/v1/application-configs/:app_name`
4. **Form Renderer** (`lib/utils/form-renderer.tsx`)
5. **Dynamic Page** (`app/projects/[projectNumber]/datasets/[datasetId]/run-application/[appName]/page.tsx`)

## Type System

### `AppFormResponse` - API Response

```typescript
export interface AppFormResponse {
  application: {
    name: string;
    class_name: string;
    category: string;
    description: string;
    required_columns: string[];
    required_params: string[];
    form_fields: AppFormField[];
    modules: string[];
  }
}

export interface AppFormField {
  name: string;                              // Unique field identifier
  type: "text" | "integer" | "float" | "number" | "select" | "multi_select" | "boolean" | "section";
  default_value?: any;                       // Default value from Ruby app
  description?: string;                      // Field description/help text
  options?: string[];                        // For select/multi_select fields
  multi_selection?: boolean;                 // Flag for multi-select behavior
  selected?: any;                            // Pre-selected values for multi-select
  section_header?: string;                   // Text for section headers
  horizontal_rule?: boolean;                 // Flag to show divider
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

## Backend Integration

### SUSHI Application Ruby Files

The backend parses SUSHI Application Ruby files (e.g., `FastqcApp.rb`) to extract configuration:

```ruby
class FastqcApp < SushiApplication
  def initialize
    @name = 'Fastqc'
    @analysis_category = 'Quality Control'
    @description = 'A quality control tool for high throughput sequence data'
    @required_columns = %w[Name Read1]
    @required_params = %w[cores]
    @modules = %w[QC]
    @inherit_tags = false
    @inherit_columns = %w[Order]
  end

  def params
    {
      'cores' => ['1', '2', '4', '8'],
      'partition' => ['normal', 'long']
    }
  end
end
```

### API Response Example

```json
// GET /api/v1/application-configs/Fastqc
{
  "application": {
    "name": "Fastqc",
    "class_name": "FastqcApp", 
    "category": "Quality Control",
    "description": "A quality control tool for high throughput sequence data",
    "required_columns": ["Name", "Read1"],
    "required_params": ["cores"],
    "form_fields": [
      {
        "name": "cores",
        "type": "select",
        "default_value": "1",
        "options": ["1", "2", "4", "8"]
      },
      {
        "name": "partition", 
        "type": "select",
        "default_value": "normal",
        "options": ["normal", "long"]
      }
    ],
    "modules": ["QC"]
  }
}
```

## Form Renderer Implementation

The form renderer handles all supported field types with proper React components:

### Field Rendering Logic

- **`renderFormField(field, value, onChange)`**: Returns field-specific JSX
  - **text**: `<input type="text">`
  - **integer**: `<input type="number" step="1">` with parseInt() 
  - **float/number**: `<input type="number" step="any">` with parseFloat()
  - **select**: `<select>` with single selection
  - **multi_select**: `<select multiple>` with array values
  - **boolean**: `<input type="checkbox">` 
  - **section**: `<h4>` headers and `<hr>` dividers

- **`FormFieldComponent(field, value, onChange)`**: Wraps fields with labels and descriptions
  - Uses `field.name` as label text
  - Shows `field.description` as help text
  - Handles section headers without labels
  - Inline labels for boolean fields

### Default Value Initialization

The `initializeFormData()` function handles type-specific defaults:

```typescript
switch (field.type) {
  case 'multi_select': defaultValue = field.selected || []; break;
  case 'boolean': defaultValue = Boolean(field.default_value); break;
  case 'integer': defaultValue = parseInt(field.default_value) || 0; break;
  case 'float': defaultValue = parseFloat(field.default_value) || 0; break;
  default: defaultValue = field.default_value || '';
}
```

## Page Implementation

The dynamic form page follows this flow:

1. **Data Fetching**: 
   - Uses `useDatasetBase(datasetId)` → `dataset, isDatasetLoading, datasetError, datasetNotFound`
   - Uses `useApplicationFormSchema(appName)` → `formConfigData, isFormConfigLoading, formConfigError`
   - Extracts `formConfig = formConfigData?.application` for form fields

2. **State Management**: 
   - `nextDatasetData` state manages next dataset name and comment fields
   - `dynamicFormData` state initialized from `formConfig.form_fields` defaults
   - Form updates trigger state changes with type-appropriate parsing

3. **Form Submission**: 
   - Uses `useJobSubmission()` hook for submission logic
   - Creates `JobSubmissionRequest` with `parameters: dynamicFormData`
   - Handles loading states, errors, and success feedback

### Key Implementation Details

```typescript
// Extract application config from API response
const formConfig = formConfigData?.application;

// Initialize form data with backend defaults  
useEffect(() => {
  if (formConfig?.form_fields) {
    setDynamicFormData(initializeFormData(formConfig.form_fields));
  }
}, [formConfig]);

// Render dynamic fields
{formConfig?.form_fields?.map((field) => (
  <FormFieldComponent
    key={field.name}
    field={field}
    value={dynamicFormData[field.name]}
    onChange={handleDynamicFieldChange}
  />
))}
```


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
