// Grouped structure for dynamic app forms

export interface AppFormField {
  name: string;
  type: "text" | "integer" | "float" | "number" | "select" | "multi_select" | "boolean" | "section";
  default_value?: any;
  description?: string;
  options?: (string | number)[];
  disabled?: boolean;
  // Optional attributes
  required?: boolean;
  placeholder?: string;
  min?: number;
  max?: number;
  multi_select?: boolean;
  file_upload?: boolean;
  hidden?: boolean;
}

export interface ParamGroup {
  id: string;
  title: string;
  description?: string;
  fields: AppFormField[];
}

export interface AppFormResponse {
  application: {
    name: string;
    category: string;
    description: string;
    required_columns: string[];
    required_params: string[];
    param_groups: ParamGroup[];
  }
}

// For form submission with dynamic data
export interface DynamicFormData {
  [fieldName: string]: any;
}
