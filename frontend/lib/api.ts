// Export feature-specific APIs
export { authApi } from './api/auth';
export { datasetApi } from './api/datasets';
export { projectApi } from './api/projects';
export { jobApi } from './api/jobs';
export { applicationApi } from './api/applications';
export { miscApi } from './api/misc';
export { httpClient } from './api/client';

// Export unified apiClient for backward compatibility
import { authApi } from './api/auth';
import { datasetApi } from './api/datasets';
import { projectApi } from './api/projects';
import { miscApi } from './api/misc';
import { httpClient } from './api/client';
import type { ProjectDatasetsResponse } from './types/project';

// Tree response types (from origin/main, Phase 2 will move these to proper location)
export type ProjectDatasetRow = ProjectDatasetsResponse['datasets'][number];

export interface TreeNode {
  id: number;
  text: string;
  parent: number | '#';
  a_attr: { href: string };
  dataset_data: ProjectDatasetRow;
}

export interface ProjectDatasetsTreeResponse {
  tree: TreeNode[];
  project_number: number;
}

export const apiClient = {
  // Auth methods
  login: authApi.login.bind(authApi),
  register: authApi.register.bind(authApi),
  logout: authApi.logout.bind(authApi),
  verifyToken: authApi.verifyToken.bind(authApi),
  getAuthenticationStatus: authApi.getAuthenticationStatus.bind(authApi),
  getAuthenticationConfig: authApi.getAuthenticationConfig.bind(authApi),
  
  // Dataset methods
  getDatasets: datasetApi.getDatasets.bind(datasetApi),
  getDataset: datasetApi.getDataset.bind(datasetApi),
  createDataset: datasetApi.createDataset.bind(datasetApi),
  
  // Project methods
  getUserProjects: projectApi.getUserProjects.bind(projectApi),
  getProjectDatasets: projectApi.getProjectDatasets.bind(projectApi),
  
  // Tree method (temporary implementation until Phase 2)
  async getProjectDatasetsTree(projectNumber: number): Promise<ProjectDatasetsTreeResponse> {
    const endpoint = `/api/v1/projects/${projectNumber}/datasets/tree`;
    return httpClient.request<ProjectDatasetsTreeResponse>(endpoint);
  },
  
  // Misc methods
  getHello: miscApi.getHello.bind(miscApi),
}; 
