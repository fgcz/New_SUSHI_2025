import { httpClient } from './client';
import { UserProjectsResponse } from '../types/project';
import { JobListResponse } from '../types/job';
import { DatasetListResponse, DatasetTreeResponse } from '../types/dataset';

export const projectApi = {
  async getUserProjects(): Promise<UserProjectsResponse> {
    return httpClient.request<UserProjectsResponse>('/projects/');
  },

  async getProjectDatasets(
    projectNumber: number,
    params: { q?: string; user?: string; page?: number; per?: number } = {}
  ): Promise<DatasetListResponse> {
    const queryString = httpClient.buildQueryString(params);
    const endpoint = `/projects/${projectNumber}/datasets${queryString ? `?${queryString}` : ''}`;
    return httpClient.request<DatasetListResponse>(endpoint);
  },

  async getGlobalDatasets(
    params: { q?: string; user?: string; page?: number; per?: number } = {}
  ): Promise<DatasetListResponse> {
    const queryString = httpClient.buildQueryString(params);
    const endpoint = `/api/v1/datasets${queryString ? `?${queryString}` : ''}`;
    return httpClient.request<DatasetListResponse>(endpoint);
  },

  async getProjectJobs(
    projectNumber: number, 
    params: { status?: string; user?: string; dataset_id?: number; from_date?: string; to_date?: string; page?: number; per?: number } = {}
  ): Promise<JobListResponse> {
    const queryString = httpClient.buildQueryString(params);
    const endpoint = `/projects/${projectNumber}/jobs${queryString ? `?${queryString}` : ``}`
    return httpClient.request<JobListResponse>(endpoint);
  },

  async getProjectDatasetsTree(projectNumber: number): Promise<{tree: DatasetTreeResponse}> {
    return httpClient.request<{tree: DatasetTreeResponse}>(`/projects/${projectNumber}/datasets/tree`);
  },

  async getDownloadAllDatasets(projectNumber: number): Promise<{id: number}> {
    return {id: projectNumber};
  },

  async getRankings(): Promise<{ rankings: Array<{ username: string; jobs_this_month: number; total_submissions: number }> }> {
    return httpClient.request('/projects/rankings');
  },

  async importDataset(
    projectNumber: number,
    data: { file: File; name: string; parentId: number | null }
  ): Promise<{ success: boolean; message: string }> {
    const formData = new FormData();
    formData.append('file', data.file);
    formData.append('name', data.name);
    if (data.parentId !== null) {
      formData.append('parent_id', data.parentId.toString());
    }

    return httpClient.request(`/projects/${projectNumber}/datasets/import`, {
      method: 'POST',
      body: formData,
      headers: {}, // Let browser set Content-Type for FormData
    });
  },

  async getApplicationsList(): Promise<{ omics_apps: string[]; retired_apps?: string[] }> {
    return httpClient.request('/applications/');
  }
};
