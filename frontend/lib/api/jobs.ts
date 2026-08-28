import { httpClient } from "./client";
import { JobFullResponse, JobListResponse, JobSubmissionRequest, JobSubmissionResponse } from "../types/job";

export const jobApi = {
  async submitJob(
    jobData: JobSubmissionRequest,
  ): Promise<JobSubmissionResponse> {
    // Transform frontend request format to backend expected format
    const backendPayload = {
      job: {
        dataset_id: jobData.dataset_id,
        app_name: jobData.app_name,
        next_dataset_name: jobData.next_dataset?.name,
        next_dataset_comment: jobData.next_dataset?.comment,
        parameters: jobData.parameters,
      }
    };

    return httpClient.request<JobSubmissionResponse>('/api/v1/jobs', {
      method: 'POST',
      body: JSON.stringify(backendPayload),
    });
  },

  async getJob(
    jobId: number
  ): Promise<JobFullResponse>{
    const { job } = await httpClient.request<{ job: JobFullResponse }>(
      `/api/v1/jobs/${jobId}`
    );
    return job;
  },

  async getAllJobs(
    params: { datasetName?: string; user?: string; page?: number; per?: number } = {}
  ): Promise<JobListResponse> {
    const queryString = httpClient.buildQueryString(params);
    const endpoint = `/api/v1/jobs${queryString ? `?${queryString}` : ''}`;
    return httpClient.request<JobListResponse>(endpoint);
  },

  async getJobScript(
    jobId: number
  ): Promise<string> {
    const { script } = await httpClient.request<{ script: string }>(
      `/api/v1/jobs/${jobId}/script`
    );
    return script;
  },

  async getJobLogs(
    jobId: number
  ): Promise<string> {
    const { logs } = await httpClient.request<{ logs: string }>(
      `/api/v1/jobs/${jobId}/logs`
    );
    return logs;
  }
};
