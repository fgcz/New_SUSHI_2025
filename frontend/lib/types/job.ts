import { DynamicFormData } from "./app-form";

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

export interface Job {
  id: number;
  status: "COMPLETED" | "FAILED" | "RUNNING" | "CANCELED+";
  user: string;
  dataset: {
    name: string;
    id: number;
  };
  time: {
    start_time: string;
    end_time?: string;
  };
}

export interface JobsListResponse {
  jobs: Job[];
}
