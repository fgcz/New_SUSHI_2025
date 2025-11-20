import { DynamicFormData } from './app-form';

export interface JobSubmissionRequest {
  project_number: number;
  dataset_id: number;
  app_name: string;
  next_dataset: {
    name: string;
    comment?: string;
  };
  parameters: DynamicFormData;
}

export interface JobSubmissionResponse {
  id: number;
  status: 'submitted' | 'running' | 'completed' | 'failed';
  created_at: string;
  message: string;
}

// Import the dynamic types from app-form
export type { DynamicFormData } from './app-form';