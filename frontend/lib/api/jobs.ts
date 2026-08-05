import { httpClient } from "./client";
import { DryRunResponse, JobFullResponse, JobListResponse, JobSubmissionRequest, JobSubmissionResponse } from "../types/job";

export const jobApi = {
  async submitJob(
    jobData: JobSubmissionRequest,
  ): Promise<JobSubmissionResponse> {
    return httpClient.request<JobSubmissionResponse>('/jobs/', {
      method: 'POST',
      body: JSON.stringify(jobData),
    });
  },

  async dryRun(
    jobData: JobSubmissionRequest,
  ): Promise<DryRunResponse> {
    return httpClient.request<DryRunResponse>('/jobs/dry-run', {
      method: 'POST',
      body: JSON.stringify(jobData),
    });
  },

  async getJob(jobId: number): Promise<JobFullResponse> {
    return httpClient.request<JobFullResponse>(`/jobs/${jobId}`);
  },

  async getAllJobs(
    params: { status?: string; user?: string; dataset_name?: string; page?: number; per?: number } = {}
  ): Promise<JobListResponse> {
    const queryString = httpClient.buildQueryString(params);
    const endpoint = `/jobs/${queryString ? `?${queryString}` : ''}`;
    return httpClient.request<JobListResponse>(endpoint);
  },

  async getJobScript(jobId: number): Promise<string> {
    const response = await httpClient.request<{ script: string }>(`/jobs/${jobId}/script`);
    return response.script;
  },

  async getJobLogs(jobId: number): Promise<{ stdout: string; stderr: string }> {
    return httpClient.request<{ stdout: string; stderr: string }>(`/jobs/${jobId}/logs`);
  }
};
