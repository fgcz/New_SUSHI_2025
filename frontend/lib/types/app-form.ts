// Simple flat structure for dynamic app forms

export interface AppFormField {
  name: string;
  type: 'text' | 'number' | 'select' | 'textarea';
  label: string;
  options?: string[];
  default?: any;
  min?: number;
  max?: number;
  required?: boolean;
  placeholder?: string;
}

export interface AppFormResponse {
  appName: string;
  fields: AppFormField[];
}

// For form submission with dynamic data
export interface DynamicFormData {
  [fieldName: string]: any;
}

export interface DynamicJobSubmissionRequest {
  project_number: number;
  dataset_id: number;
  app_name: string;
  next_dataset: {
    name: string;
    comment?: string;
  };
  parameters: DynamicFormData;
}