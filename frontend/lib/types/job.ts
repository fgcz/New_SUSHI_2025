import { DynamicFormData } from "./app-form";

export interface JobListResponse {
  jobs: JobMinimal[];
  pagination: {
    total_count: number;
    page: number;
    per: number;
    total_pages: number;
  };
  filters: {
    status: string;
    user: string;
  };
  project_number: number;
}

export interface JobFullResponse {
  id: number;
  status: string;
  user: string;
  input_dataset_id: number;
  next_dataset_id: number;
  created_at: string;
  script_path: string;
  submit_job_id: number;
  start_time: string;
  end_time: string;
  updated_at: string;
}

export interface JobMinimal {
  id: number;
  status: string;
  user: string;
  dataset: {
    id: number;
    name: string;
  } | null;
  time: {
    start_time: string;
    end_time?: string;
  };
  created_at: string;
}

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
  status: "submitted" | "running" | "completed" | "failed";
  created_at: string;
  message: string;
}
