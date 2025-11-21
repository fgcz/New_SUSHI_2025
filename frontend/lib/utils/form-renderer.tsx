import React from 'react';
import { AppFormField, DynamicFormData } from '@/lib/types';

interface FieldRendererProps {
  field: AppFormField;
  value: any;
  onChange: (fieldName: string, value: any) => void;
}

export const renderFormField = ({ field, value, onChange }: FieldRendererProps): JSX.Element => {
  const baseClasses = "px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500";
  
  // Handle section headers
  if (field.type === 'section') {
    return (
      <div className="col-span-full">
        {field.section_header && (
          <h4 className="text-lg font-medium text-gray-900 mb-4 pt-4 border-t border-gray-200">
            {field.section_header}
          </h4>
        )}
        {field.horizontal_rule && <hr className="my-4 border-gray-200" />}
      </div>
    );
  }
  
  switch (field.type) {
    case 'select':
      return (
        <select
          id={field.name}
          name={field.name}
          value={value !== undefined ? value : field.default_value || ''}
          onChange={(e) => onChange(field.name, e.target.value)}
          className={`${baseClasses} bg-white w-full`}
        >
          {field.options?.map((option, index) => (
            <option key={index} value={option}>
              {option}
            </option>
          ))}
        </select>
      );

    case 'multi_select':
      return (
        <select
          id={field.name}
          name={field.name}
          multiple
          value={Array.isArray(value) ? value : (field.selected || [])}
          onChange={(e) => {
            const selectedValues = Array.from(e.target.selectedOptions, option => option.value);
            onChange(field.name, selectedValues);
          }}
          className={`${baseClasses} bg-white w-full`}
          size={Math.min(field.options?.length || 3, 5)}
        >
          {field.options?.map((option, index) => (
            <option key={index} value={option}>
              {option}
            </option>
          ))}
        </select>
      );

    case 'boolean':
      return (
        <div className="flex items-center">
          <input
            type="checkbox"
            id={field.name}
            name={field.name}
            checked={value !== undefined ? Boolean(value) : Boolean(field.default_value)}
            onChange={(e) => onChange(field.name, e.target.checked)}
            className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
          />
          <label htmlFor={field.name} className="ml-2 text-sm text-gray-700">
            {field.description || 'Enable option'}
          </label>
        </div>
      );

    case 'integer':
      return (
        <input
          type="number"
          id={field.name}
          name={field.name}
          value={value !== undefined ? value : field.default_value || ''}
          step="1"
          onChange={(e) => onChange(field.name, parseInt(e.target.value) || 0)}
          className={`${baseClasses} w-full`}
        />
      );

    case 'float':
    case 'number':
      return (
        <input
          type="number"
          id={field.name}
          name={field.name}
          value={value !== undefined ? value : field.default_value || ''}
          step="any"
          onChange={(e) => onChange(field.name, parseFloat(e.target.value) || 0)}
          className={`${baseClasses} w-full`}
        />
      );

    case 'text':
    default:
      return (
        <input
          type="text"
          id={field.name}
          name={field.name}
          value={value !== undefined ? value : field.default_value || ''}
          onChange={(e) => onChange(field.name, e.target.value)}
          className={`${baseClasses} w-full`}
        />
      );
  }
};

interface FormFieldComponentProps {
  field: AppFormField;
  value: any;
  onChange: (fieldName: string, value: any) => void;
}

export const FormFieldComponent: React.FC<FormFieldComponentProps> = ({ field, value, onChange }) => {
  // Handle section headers - they don't need labels
  if (field.type === 'section') {
    return <>{renderFormField({ field, value, onChange })}</>;
  }

  // Handle boolean fields - they have their own label inline
  if (field.type === 'boolean') {
    return <div>{renderFormField({ field, value, onChange })}</div>;
  }

  return (
    <div>
      <label htmlFor={field.name} className="block text-sm font-medium text-gray-700 mb-2">
        {field.name}
        {field.description && (
          <span className="text-gray-500 text-xs block font-normal">
            {field.description}
          </span>
        )}
      </label>
      {renderFormField({ field, value, onChange })}
    </div>
  );
};

// Utility function to initialize form data with defaults
export const initializeFormData = (fields: AppFormField[]): DynamicFormData => {
  const formData: DynamicFormData = {};
  fields.forEach((field) => {
    // Skip section headers as they don't have values
    if (field.type === 'section') return;
    
    let defaultValue = field.default_value;
    
    // Handle different field types
    switch (field.type) {
      case 'multi_select':
        defaultValue = field.selected || [];
        break;
      case 'boolean':
        defaultValue = Boolean(defaultValue);
        break;
      case 'integer':
        defaultValue = defaultValue !== undefined ? parseInt(String(defaultValue)) : 0;
        break;
      case 'float':
      case 'number':
        defaultValue = defaultValue !== undefined ? parseFloat(String(defaultValue)) : 0;
        break;
      default:
        defaultValue = defaultValue !== undefined ? defaultValue : '';
    }
    
    formData[field.name] = defaultValue;
  });
  return formData;
};