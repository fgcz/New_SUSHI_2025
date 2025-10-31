import { httpClient } from './client';
import { UserProjectsResponse, ProjectDatasetsResponse } from '../types/project';

export const projectApi = {
  async getUserProjects(): Promise<UserProjectsResponse> {
    return httpClient.request<UserProjectsResponse>('/api/v1/projects');
  },

  async getProjectDatasets(
    projectNumber: number, 
  ): Promise<ProjectDatasetsResponse> {
    const endpoint = `/api/v1/projects/${projectNumber}/datasets`;
    return httpClient.request<ProjectDatasetsResponse>(endpoint);
  },

  async getProjectDatasets2(
    projectNumber: number, 
    params: { datasetName?: string; user?: string; page?: number; per?: number } = {}
  ): Promise<ProjectDatasetsResponse> {
    const queryString = httpClient.buildQueryString(params);
    const endpoint = `/api/v1/projects/${projectNumber}/datasets${queryString ? `?${queryString}` : ''}`;
    return httpClient.request<ProjectDatasetsResponse>(endpoint);
  },
};
