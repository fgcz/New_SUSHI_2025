export interface Dataset {
  id: number;
  name: string;
  created_at: string;
  user: string;
}

export interface ProjectDataset {
  id: number;
  name: string;
  sushi_app_name?: string;
  completed_samples?: number;
  samples_length?: number;
  parent_id?: number | null;
  children_ids?: number[];
  user_login?: string | null;
  created_at: string;
  bfabric_id?: number | null;
  project_number: number;
}

export interface DatasetsResponse {
  datasets: Dataset[];
  total_count: number;
  current_user: string;
}

export interface DatasetResponse {
  dataset: Dataset;
}

export interface CreateDatasetResponse {
  dataset: Dataset;
  message: string;
}