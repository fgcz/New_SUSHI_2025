export interface DatasetListResponse {
  datasets: DatasetMinimal[];
  pagination: {
    total_count: number;
    page: number;
    per: number;
    total_pages: number;
  }
  filters: {
    q: string;
  }
  project_number: number;
}

export interface DatasetFullResponse {
  id: number;
  name: string;
  created_at: string;
  user?: string | null;
  project_number: number;
  samples_count?: number;
  completed_samples?: number;
  parent_id?: number | null;
  children_ids?: number[];
  bfabric_id?: number | null;
  order_ids?: number[];
  comment?: string;
  sushi_app_name?: string;
  samples: DatasetSample[];
  applications: DatasetAppCategory[];
  data_paths: string[];
}

interface DatasetMinimal {
  id: number;
  name: string;
  sushi_app_name?: string;
  completed_samples?: number;
  samples_count?: number;
  parent_id?: number | null;
  children_ids?: number[];
  user_login?: string | null;
  created_at: string;
  bfabric_id?: number | null;
  order_ids?: number[];
  project_number: number;
  comment?: string;
}

// -------------------- SAMPLE 

export interface DatasetSample {
    id: number;
    name: string;
    [columnName: string]: any | undefined;
}

// -------------------- APP 
export interface DatasetAppCategory {
  category: string;
  apps: DatasetApp[];
}

interface DatasetApp {
  name: string;
  description: string;
}

// -------------------- TREE
export interface DatasetTreeNode {
  id: number;
  name: string;
  comment?: string;
  parent: number | "#";
  children_count: number;
}

export type DatasetTreeResponse = {
  tree: DatasetTreeNode[];
  project_number?: number;
}

// Legacy type aliases for backward compatibility
export type ProjectDataset = DatasetFullResponse;
export type ProjectDatasetsResponse = DatasetListResponse;
