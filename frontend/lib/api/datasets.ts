import { httpClient } from './client';
import { DatasetsResponse, Dataset, CreateDatasetResponse, DatasetSamplesResponse, DatasetRunnableAppsResponse, DatasetTreeResponse} from '../types/dataset';

export const datasetApi = {
    async getDatasets(): Promise<DatasetsResponse> {
        return httpClient.request<DatasetsResponse>('/api/v1/datasets');
    },

    async getDataset(id: number): Promise<Dataset> {
        return httpClient.request<Dataset>(`/api/v1/datasets/${id}`);
    },

    // async createDataset(name: string): Promise<CreateDatasetResponse> {
    //     return httpClient.request<CreateDatasetResponse>('/api/v1/datasets', {
    //         method: 'POST',
    //         body: JSON.stringify({ dataset: { name } }),
    //     });
    // },

    async getDatasetTree(id: number): Promise<DatasetTreeResponse> {
        return httpClient.request<DatasetTreeResponse>(`/api/v1/datasets/${id}/tree`);
    },


    async getDatasetSamples(id: number): Promise<DatasetSamplesResponse> {
        return httpClient.request<DatasetSamplesResponse>(`/api/v1/datasets/${id}/samples`);
    },

    async getRunnableApps(id: number): Promise<DatasetRunnableAppsResponse> {
        return httpClient.request<DatasetRunnableAppsResponse>(`/api/v1/datasets/${id}/runnable_apps`);
    },
};
