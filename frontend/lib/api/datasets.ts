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
            id: 130,
            name: "EzPyzENACTAPP",
            comment: "Main project directory",
            parent: "#"
          },
          {
            id: 129,
            name: "Dataset Analysis",
            parent: 130
          },
          {
            id: 133,
            name: "Raw Data",
            comment: "Original data files",
            parent: 129
          },
          {
            id: 141,
            name: "Analysis Results", 
            comment: "Processed analysis output",
            parent: 129
          }
        ]);
      }, 500);
    });
  },
};
