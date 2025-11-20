import { httpClient } from "./client";
import { JobSubmissionRequest, JobSubmissionResponse } from "../types/job";

export const jobApi = {
  async submitJob(
    jobData: JobSubmissionRequest | JobSubmissionRequest,
  ): Promise<JobSubmissionResponse> {
    // Mock implementation - replace with actual API call when backend is ready
    return new Promise((resolve) => {
      setTimeout(() => {
        resolve({
          id: Math.floor(Math.random() * 10000),
          status: "submitted",
          created_at: new Date().toISOString(),
          message: `MOCK RESPONSE`,
        });
        // throw new Error("I'm THROWING");
      }, 2000);
    });

    // Future implementation when backend is ready:
    // return httpClient.request<JobSubmissionResponse>('/api/v1/jobs', {
    //   method: 'POST',
    //   body: JSON.stringify(jobData),
    // });
  },
};
