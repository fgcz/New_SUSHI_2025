import React from 'react';
import { AppFormField, DynamicFormData } from '@/lib/types';

interface FieldRendererProps {
  field: AppFormField;
  value: any;
  onChange: (fieldName: string, value: any) => void;
}

export const renderFormField = ({ field, value, onChange }: FieldRendererProps): JSX.Element => {
  const baseClasses = "px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500";
  
  switch (field.type) {
    case 'select':
      return (
        <select
          id={field.name}
          name={field.name}
          value={value || field.default || ''}
          onChange={(e) => onChange(field.name, e.target.value)}
          required={field.required}
          className={`${baseClasses} bg-white ${field.name === 'cores' || field.name === 'partition' ? 'w-40' : 'w-full'}`}
        >
          {field.options?.map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </select>
      );

    case 'number':
      return (
        <input
          type="number"
          id={field.name}
          name={field.name}
          value={value !== undefined ? value : field.default || ''}
          min={field.min}
          max={field.max}
          step={field.name === 'resolution' ? 0.1 : 1} // Special handling for resolution field
          onChange={(e) => onChange(field.name, Number(e.target.value))}
          required={field.required}
          placeholder={field.placeholder}
          className={`${baseClasses} w-full`}
        />
      );

    case 'textarea':
      return (
        <textarea
          id={field.name}
          name={field.name}
          value={value || field.default || ''}
          onChange={(e) => onChange(field.name, e.target.value)}
          required={field.required}
          placeholder={field.placeholder}
          rows={3}
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
          value={value || field.default || ''}
          onChange={(e) => onChange(field.name, e.target.value)}
          required={field.required}
          placeholder={field.placeholder}
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
  return (
    <div>
      <label htmlFor={field.name} className="block text-sm font-medium text-gray-700 mb-2">
        {field.label}
        {field.required && <span className="text-red-500 ml-1">*</span>}
      </label>
      {renderFormField({ field, value, onChange })}
    </div>
  );
};

// Utility function to initialize form data with defaults
export const initializeFormData = (fields: AppFormField[]): DynamicFormData => {
  const formData: DynamicFormData = {};
  fields.forEach((field) => {
    formData[field.name] = field.default !== undefined ? field.default : '';
  });
  return formData;
};