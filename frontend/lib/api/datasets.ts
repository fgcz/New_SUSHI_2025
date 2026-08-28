import { httpClient } from './client';
import { DatasetFullResponse, DatasetTreeResponse } from '../types/dataset';

export const datasetApi = {
    async getDataset(id: number): Promise<DatasetFullResponse> {
        return httpClient.request<DatasetFullResponse>(`/api/v1/datasets/${id}`);
    },
    async getDatasetTree(id: number): Promise<DatasetTreeResponse> {
        return httpClient.request<DatasetTreeResponse>(`/api/v1/datasets/${id}/tree`);
    },

    // Name and comment are the only two fields legacy's dataset page edits
    // (data_set_controller#edit_name and #add_comment).
    async addComment(datasetId: number, comment: string): Promise<void> {
        await httpClient.request(`/api/v1/datasets/${datasetId}`, {
            method: 'PATCH',
            body: JSON.stringify({ dataset: { comment } }),
        });
    },
    async renameDataset(datasetId: number, newName: string): Promise<void> {
        await httpClient.request(`/api/v1/datasets/${datasetId}`, {
            method: 'PATCH',
            body: JSON.stringify({ dataset: { name: newName } }),
        });
    },
    async downloadDataset(datasetId: number): Promise<void> {
        await httpClient.download(`/api/v1/datasets/${datasetId}/tsv`, `dataset_${datasetId}.tsv`);
    },
    async getDatasetDataFolder(datasetId: number): Promise<{ path: string }> {
        const { paths } = await httpClient.request<{ paths: string[] }>(
            `/api/v1/datasets/${datasetId}/paths`
        );
        return { path: paths[0] || '' };
    },
    async getScriptsPath(datasetId: number): Promise<{ path: string }> {
        const { paths } = await httpClient.request<{ paths: string[] }>(
            `/api/v1/datasets/${datasetId}/paths`
        );
        return { path: paths[0] ? `${paths[0]}/scripts` : '' };
    },
    async getDatasetParameters(datasetId: number): Promise<Record<string, string>> {
        const { parameters } = await httpClient.request<{ parameters: Record<string, unknown> }>(
            `/api/v1/datasets/${datasetId}/parameters`
        );
        return Object.fromEntries(
            Object.entries(parameters).map(([key, value]) => [key, String(value)])
        );
    },
    async setBFabricId(datasetId: number, bfabricId: string): Promise<void> {
        await httpClient.request(`/v1/datasets/${datasetId}/bfabric-id`, {
            method: 'PUT',
            body: JSON.stringify({ bfabric_id: bfabricId }),
        });
    },
    async deleteDataset(datasetId: number): Promise<void> {
        await httpClient.request(`/v1/datasets/${datasetId}`, { method: 'DELETE' });
    },
    async getResubmitData(datasetId: number): Promise<{ appName: string; parameters: Record<string, any> }> {
        const { app_name, parameters } = await httpClient.request<{
            app_name: string;
            parameters: Record<string, any>;
        }>(`/api/v1/datasets/${datasetId}/resubmit`);
        return { appName: app_name, parameters };
    },

    // NOT IMPLEMENTED — legacy's merge takes a SECOND dataset and a name for the
    // result (data_set_controller#merge_with_dataset), which this signature has
    // no way to supply. It needs a picker in the UI before it can have a backend.
    async mergeDataset(datasetId: number): Promise<void> {
        throw new Error('Merging datasets is not implemented yet: it needs a second dataset to merge with.');
    },
    // NOT IMPLEMENTED — legacy runs `update_resource_size -w <workunit>` as a
    // shell command from its show page. No caller in this UI today.
    async updateSize(datasetId: number): Promise<void> {
        throw new Error('Updating the resource size is not implemented yet.');
    },
    // NOT IMPLEMENTED — legacy's announce is a three-step template flow
    // (announce_template_set -> announce_replace_set -> announce) that composes
    // an email from announce_templates/*.txt. No caller in this UI today.
    async announceDataset(datasetId: number): Promise<void> {
        throw new Error('Announcing a dataset is not implemented yet.');
    },
    // NOT IMPLEMENTED — GEO upload is a separate daemon that talks to the
    // /internal/legacy bridge, not something SUSHI's web layer performs.
    async geoUploader(datasetId: number): Promise<void> {
        throw new Error('GEO upload is not driven from SUSHI: it runs as its own daemon.');
    },
};
