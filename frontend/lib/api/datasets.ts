import { httpClient } from './client';
import { DatasetsResponse, ProjectDataset, DatasetTreeResponse} from '../types/dataset';

export const datasetApi = {
    async getDatasets(): Promise<DatasetsResponse> {
        return httpClient.request<DatasetsResponse>('/api/v1/datasets');
    },

    async getDataset(id: number): Promise<ProjectDataset> {
        return httpClient.request<ProjectDataset>(`/api/v1/datasets/${id}`);
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
};
