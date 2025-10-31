// Simple flat structure for dynamic app forms

export interface AppFormField {
  name: string;
  type: "text" | "integer" | "float" | "number" | "select" | "multi_select" | "boolean" | "section";
  default_value?: any;
  description?: string;
  options?: string[];
  multi_selection?: boolean;
  selected?: any;
  section_header?: string;
  horizontal_rule?: boolean;
}

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
    // inherit_tags: boolean;
    // inherit_columns: string[];
  }
}

// For form submission with dynamic data
export interface DynamicFormData {
  [fieldName: string]: any;
}
