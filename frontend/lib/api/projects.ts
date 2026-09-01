import { httpClient } from './client';
import { UserProjectsResponse } from '../types/project';
import { JobListResponse } from '../types/job';
import { DatasetListResponse, DatasetTreeResponse } from '../types/dataset';

export const projectApi = {
  async getUserProjects(): Promise<UserProjectsResponse> {
    return httpClient.request<UserProjectsResponse>('/api/v1/projects');
  },

  async getProjectDatasets(
    projectNumber: number, 
    params: { datasetName?: string; user?: string; page?: number; per?: number } = {}
  ): Promise<DatasetListResponse> {
    const queryString = httpClient.buildQueryString(params);
    const endpoint = `/api/v1/projects/${projectNumber}/datasets${queryString ? `?${queryString}` : ''}`;
    return httpClient.request<DatasetListResponse>(endpoint);
  },

  async getProjectJobs(
    projectNumber: number, 
    params: { status?: string; user?: string; dataset_id?: number; from_date?: string; to_date?: string; page?: number; per?: number } = {}
  ): Promise<JobListResponse> {
    const queryString = httpClient.buildQueryString(params);
    const endpoint = `/api/v1/projects/${projectNumber}/jobs${queryString ? `?${queryString}` : ``}`
    return httpClient.request<JobListResponse>(endpoint);
  },

  async getProjectDatasetsTree(projectNumber: number): Promise<{tree: DatasetTreeResponse}> {
    return httpClient.request<{tree: DatasetTreeResponse}>(`/api/v1/projects/${projectNumber}/datasets/tree`);
  },

  // Downloads the project's dataset LIST as TSV (legacy
  // data_set_controller#save_project_dataset_list_as_tsv). The id is kept in the
  // return value because the caller still uses it.
  async getDownloadAllDatasets(projectNumber: number): Promise<{id: number}> {
    await httpClient.download(
      `/api/v1/projects/${projectNumber}/datasets/tsv`,
      `p${projectNumber}_datasets.tsv`
    );
    return { id: projectNumber };
  },

  async validateDatasetId(user: string, datasetId: number): Promise<{ projectId: number }> {
    const dataset = await httpClient.request<{ project_number: number }>(
      `/api/v1/datasets/${datasetId}`
    );
    if (!dataset.project_number) {
      throw new Error(`Dataset ${datasetId} has no project`);
    }
    return { projectId: dataset.project_number };
  },

  async getRankings(): Promise<{ rankings: Array<{ username: string; jobsThisMonth: number; totalSubmissions: number }> }> {
    return httpClient.request<{ rankings: Array<{ username: string; jobsThisMonth: number; totalSubmissions: number }> }>(
      '/api/v1/rankings'
    );
  },

  async importDataset(
    projectNumber: number,
    data: { file: File; name: string; parentId: number | null }
  ): Promise<void> {
    // The backend takes the TSV as text, so the file is read here rather than
    // uploaded as multipart.
    const tsvContent = await data.file.text();
    await httpClient.request('/api/v1/datasets/from_tsv', {
      method: 'POST',
      body: JSON.stringify({
        tsv_content: tsvContent,
        dataset_name: data.name,
        project_number: projectNumber,
        parent_id: data.parentId,
      }),
    });
  },

  async getProjectIdFromJob(jobId: number): Promise<{ projectId: number }> {
    const { job } = await httpClient.request<{ job: { project_number: number | null } }>(
      `/api/v1/jobs/${jobId}`
    );
    if (!job.project_number) {
      throw new Error(`Job ${jobId} has no project`);
    }
    return { projectId: job.project_number };
  }
};
