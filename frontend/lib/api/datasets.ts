import { httpClient } from './client';
import { DatasetsResponse, DatasetResponse, CreateDatasetResponse } from '../types/dataset';
import { RunnableAppsResponse } from '../types/runnable-apps';
import { FolderTreeResponse } from '../types/folder-tree';

export const datasetApi = {
  async getDatasets(): Promise<DatasetsResponse> {
    return httpClient.request<DatasetsResponse>('/api/v1/datasets');
  },

  async getDataset(id: number): Promise<DatasetResponse> {
    return httpClient.request<DatasetResponse>(`/api/v1/datasets/${id}`);
  },

  async createDataset(name: string): Promise<CreateDatasetResponse> {
    return httpClient.request<CreateDatasetResponse>('/api/v1/datasets', {
      method: 'POST',
      body: JSON.stringify({ dataset: { name } }),
    });
  },

  async getRunnableApps(id: number): Promise<RunnableAppsResponse> {
    return new Promise((resolve) => {
      setTimeout(() => {
        resolve([
          {
            category: "singleCell",
            applications: ["cellRanger", "seurat", "scanpy"]
          },
          {
            category: "genomics", 
            applications: ["blast", "bwa", "gatk"]
          }
        ]);
      }, 500);
    });
  },

  async getFolderTree(id: number): Promise<FolderTreeResponse> {
    return new Promise((resolve) => {
      setTimeout(() => {
        resolve([
          {
            id: 1,
            name: "Project Root",
            comment: "Main project directory",
            parent: "#"
          },
          {
            id: 2,
            name: "Dataset Analysis",
            parent: 1
          },
          {
            id: id, // Use the actual dataset ID from the parameter
            name: `Dataset ${id}`,
            comment: "Current dataset folder",
            parent: 2
          },
          {
            id: 100,
            name: "Raw Data",
            comment: "Original data files",
            parent: id
          },
          {
            id: 101,
            name: "Analysis Results",
            parent: id
          },
          {
            id: 102,
            name: "QC Reports",
            comment: "Quality control reports",
            parent: id
          },
          {
            id: 200,
            name: "FASTQ Files",
            parent: 100
          },
          {
            id: 201,
            name: "Metadata",
            parent: 100
          },
          {
            id: 300,
            name: "Filtered Data",
            parent: 101
          },
          {
            id: 301,
            name: "Summary Statistics",
            parent: 101
          }
        ]);
      }, 500);
    });
  },
};
