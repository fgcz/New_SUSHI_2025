import { httpClient } from './client';
import { UserProjectsResponse } from '../types/project';
import { JobListResponse } from '../types/job';
import { DatasetListResponse, DatasetTreeResponse } from '../types/dataset';

export const projectApi = {
  async getUserProjects(user: string): Promise<UserProjectsResponse> {
    return httpClient.request<UserProjectsResponse>(`/projects/${user}`);
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

  async validateDatasetId(user: string, datasetId: number): Promise<{ projectId: number }> {
    // Mock API call - simulate validation
    // For demo: IDs <= 0 or > 99999 are considered invalid
    if (datasetId <= 0 || datasetId > 99999) {
      return Promise.reject(new Error(`Dataset ${datasetId} not found`));
    }
    return Promise.resolve({ projectId: 1001 });
  },

  async getRankings(): Promise<{ rankings: Array<{ username: string; jobsThisMonth: number; totalSubmissions: number }> }> {
    return Promise.resolve({
      rankings: [
        { username: 'alice.smith', jobsThisMonth: 142, totalSubmissions: 3847 },
        { username: 'bob.jones', jobsThisMonth: 98, totalSubmissions: 2156 },
        { username: 'carol.williams', jobsThisMonth: 87, totalSubmissions: 1893 },
        { username: 'david.brown', jobsThisMonth: 76, totalSubmissions: 1654 },
        { username: 'emma.davis', jobsThisMonth: 65, totalSubmissions: 1432 },
        { username: 'frank.miller', jobsThisMonth: 54, totalSubmissions: 1287 },
        { username: 'grace.wilson', jobsThisMonth: 43, totalSubmissions: 956 },
        { username: 'henry.moore', jobsThisMonth: 38, totalSubmissions: 842 },
        { username: 'iris.taylor', jobsThisMonth: 29, totalSubmissions: 634 },
        { username: 'jack.anderson', jobsThisMonth: 21, totalSubmissions: 478 },
      ],
    });
  },

  async importDataset(
    projectNumber: number,
    data: { file: File; name: string; parentId: number | null }
  ): Promise<void> {
    // Mock API call - in real implementation would upload file and create dataset
    console.log('Mock importDataset called:', { projectNumber, name: data.name, parentId: data.parentId, fileName: data.file.name });
    return Promise.resolve();
  },

  async getProjectIdFromJob(jobId: number): Promise<{ projectId: number }> {
    // Mock API call - returns the project ID associated with a job
    return Promise.resolve({ projectId: 1001 });
  },

  async getApplicationsList(): Promise<{ sushiApps: string[]; retiredApps: string[] }> {
    return Promise.resolve({
      sushiApps: [
        'FastQC',
        'STAR',
        'Bowtie2',
        'BWA',
        'Salmon',
        'Kallisto',
        'DESeq2',
        'EdgeR',
        'Cufflinks',
        'HTSeq',
      ],
      retiredApps: [
        'TopHat',
        'Cuffquant',
        'Cuffdiff',
        'Cuffmerge',
        'Cuffcompare',
        'CuffnormApp',
        'SoapAligner',
        'MAQ',
        'ELAND',
        'Novoalign',
      ],
    });
  }
};
