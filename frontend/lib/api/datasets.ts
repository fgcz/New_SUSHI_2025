import { httpClient } from './client';
import { DatasetsResponse, DatasetResponse, CreateDatasetResponse } from '../types/dataset';

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
};