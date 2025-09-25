import { ProjectDataset } from './dataset';

export interface Project { 
  number: number;
}

export interface UserProjectsResponse { 
  projects: Project[]; 
  current_user: string;
}

export interface ProjectDatasetsResponse {
  datasets: ProjectDataset[];
  total_count: number;
  page: number;
  per: number;
  project_number: number;
}