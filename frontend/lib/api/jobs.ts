import { httpClient } from "./client";
import { JobsListResponse, JobSubmissionRequest, JobSubmissionResponse } from "../types/job";

export const jobApi = {
  async submitJob(
    jobData: JobSubmissionRequest,
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

  async getJobsList(
    projectId: number, 
    params: { datasetName?: string; user?: string; status?: string } = {}
  ): Promise<JobsListResponse> {
    return new Promise((resolve) => {
      setTimeout(() => {
        // Mock base data
        const baseJobs = [
          {
            id: 1001,
            status: "COMPLETED",
            user: "rdomi",
            dataset: {
              name: "Customer Analytics Q3",
              id: 273
            },
            time: {
              start_time: "2024-10-08T09:15:30Z",
              end_time: "2024-10-08T09:18:45Z"
            }
          },
          {
            id: 1002,
            status: "RUNNING",
            user: "fnoe",
            dataset: {
              name: "Product Recommendations",
              id: 266
            },
            time: {
              start_time: "2024-10-09T14:22:10Z"
            }
          },
          {
            id: 1003,
            status: "FAILED",
            user: "rdomi",
            dataset: {
              name: "Sales Data ETL",
              id: 224
            },
            time: {
              start_time: "2024-10-09T11:05:20Z",
              end_time: "2024-10-09T11:07:33Z"
            }
          }
        ];

        // Duplicate jobs 50 times each to get 150 total jobs (like in the page)
        const allJobs = [];
        for (let i = 0; i < 50; i++) {
          baseJobs.forEach((job, index) => {
            allJobs.push({
              ...job,
              id: 1000 + (i * 3) + index + 1,
              dataset: {
                ...job.dataset,
                name: `${job.dataset.name} #${i + 1}`,
                id: job.dataset.id + i
              }
            });
          });
        }

        // Apply filters
        const filteredJobs = allJobs.filter(job => {
          const matchesDatasetName = !params.datasetName || 
            job.dataset.name.toLowerCase().includes(params.datasetName.toLowerCase());
          const matchesUser = !params.user || 
            job.user.toLowerCase().includes(params.user.toLowerCase());
          const matchesStatus = !params.status || 
            job.status.toLowerCase().includes(params.status.toLowerCase());
          
          return matchesDatasetName && matchesUser && matchesStatus;
        });

        resolve({
          jobs: filteredJobs
        });
      }, 1500);
    });

    // Future implementation when backend is ready:
    // return httpClient.request<JobsListResponse>(`/api/v1/projects/${projectId}/jobs`, {
    //   method: 'GET',
    // });
  }
};

