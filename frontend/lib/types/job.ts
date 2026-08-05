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
    status: string | null;
    user: string | null;
    dataset_name?: string | null;
    q?: string | null;
  };
  project_number?: number;
}

export interface JobFullResponse {
  id: number;
  project_number: number | null;
  status: string;
  user: string;
  input_dataset_id: number;
  next_dataset_id: number;
  created_at: string;
  script_path: string | null;
  stdout_path: string | null;
  stderr_path: string | null;
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
  job_id: number;
  output_dataset_id: number;
  slurm_job_id: string;
  status: "submitted" | "running" | "completed" | "failed";
  message: string;
}

export interface DryRunResponse {
  dry_run: true;
  script_path: string;
  stdout_path: string;
  stderr_path: string;
  result_dir: string;
  input_dataset_tsv_path: string;
  resources: {
    cores: number;
    ram: number;
    scratch: number;
    partition: string;
  };
}
