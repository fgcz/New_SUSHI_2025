export interface Dataset {
  id: number;
  name: string;
  created_at: string;
  user: string;
  project_number?: number;
}

export interface ProjectDataset {
  id: number;
  name: string;
  sushi_app_name?: string;
  completed_samples?: number;
  samples_count?: number;
  parent_id?: number | null;
  children_ids?: number[];
  user?: string | null;
  created_at: string;
  bfabric_id?: number | null;
  order_id?: number | null;
  project_number: number;
  applications: DatasetAppCategory[],
  samples: DatasetSample[];
}

export interface DatasetsResponse {
  datasets: Dataset[];
  total_count: number;
  current_user: string;
}

export interface CreateDatasetResponse {
  dataset: Dataset;
  message: string;
}

export interface DatasetSample {
    id: number;
    name: string;
    [columnName: string]: any | undefined;
}

export type DatasetSamplesResponse = DatasetSample[];

export interface DatasetAppCategory {
  category: string;
  apps: DatasetApp[];
}

interface DatasetApp{
  class_name: string;
  description: string;
}

export interface DatasetTreeNode {
  id: number;
  name: string;
  comment?: string;
  parent: number | "#";
}

export type DatasetTreeResponse = DatasetTreeNode[];

