import { httpClient } from './client';
import { DatasetFullResponse, DatasetTreeResponse } from '../types/dataset';

export const datasetApi = {
    async getDataset(id: number): Promise<DatasetFullResponse> {
        return httpClient.request<DatasetFullResponse>(`/datasets/${id}`);
    },
    async getDatasetTree(id: number): Promise<DatasetTreeResponse> {
        return httpClient.request<DatasetTreeResponse>(`/datasets/${id}/tree`);
    },

    async addComment(datasetId: number, comment: string): Promise<void> {
        await httpClient.request(`/datasets/${datasetId}/comment?comment=${encodeURIComponent(comment)}`, {
            method: 'POST',
        });
    },

    async renameDataset(datasetId: number, newName: string): Promise<void> {
        await httpClient.request(`/datasets/${datasetId}/name?new_name=${encodeURIComponent(newName)}`, {
            method: 'PATCH',
        });
    },

    async downloadDataset(datasetId: number): Promise<{ downloadUrl: string }> {
        const response = await httpClient.request<{ download_url: string }>(
            `/datasets/${datasetId}/download`
        );
        return { downloadUrl: response.download_url };
    },

    async getScriptsPath(datasetId: number): Promise<{ path: string }> {
        return httpClient.request<{ path: string }>(`/datasets/${datasetId}/scripts-path`);
    },

    async mergeDataset(datasetId: number, targetDatasetId: number): Promise<void> {
        await httpClient.request(
            `/datasets/${datasetId}/merge?target_dataset_id=${targetDatasetId}`,
            { method: 'POST' }
        );
    },

    async getDatasetParameters(datasetId: number): Promise<Record<string, string>> {
        return httpClient.request<Record<string, string>>(`/datasets/${datasetId}/parameters`);
    },

    async updateSize(datasetId: number): Promise<void> {
        await httpClient.request(`/datasets/${datasetId}/update-size`, {
            method: 'POST',
        });
    },

    async setBFabricId(datasetId: number, bfabricId: string): Promise<void> {
        await httpClient.request(
            `/datasets/${datasetId}/bfabric-id?bfabric_id=${encodeURIComponent(bfabricId)}`,
            { method: 'PATCH' }
        );
    },

    async announceDataset(datasetId: number): Promise<void> {
        await httpClient.request(`/datasets/${datasetId}/announce`, {
            method: 'POST',
        });
    },

    async deleteDataset(datasetId: number): Promise<void> {
        await httpClient.request(`/datasets/${datasetId}`, {
            method: 'DELETE',
        });
    },

    async getResubmitData(datasetId: number): Promise<{ appName: string; parameters: Record<string, any> }> {
        const response = await httpClient.request<{ app_name: string; parameters: Record<string, any> }>(
            `/datasets/${datasetId}/resubmit-data`
        );
        return {
            appName: response.app_name,
            parameters: response.parameters,
        };
    },
};
