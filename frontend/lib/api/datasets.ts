import { httpClient } from './client';
import { DatasetFullResponse, DatasetTreeResponse } from '../types/dataset';

export const datasetApi = {
    async getDataset(id: number): Promise<DatasetFullResponse> {
        return httpClient.request<DatasetFullResponse>(`/datasets/${id}`);
    },
    async getDatasetTree(id: number): Promise<DatasetTreeResponse> {
        return httpClient.request<DatasetTreeResponse>(`/datasets/${id}/tree`);
    },

    // Mock API functions for dataset actions
    async addComment(datasetId: number, comment: string): Promise<void> {
        return Promise.resolve();
    },
    async renameDataset(datasetId: number, newName: string): Promise<void> {
        return Promise.resolve();
    },
    async downloadDataset(datasetId: number): Promise<void> {
        return Promise.resolve();
    },
    async getScriptsPath(datasetId: number): Promise<{ path: string }> {
        return Promise.resolve({ path: 'p1001/whatever_path_we_get' });
    },
    async mergeDataset(datasetId: number): Promise<void> {
        return Promise.resolve();
    },
    async getDatasetParameters(datasetId: number): Promise<Record<string, string>> {
        return Promise.resolve({
            cores: '8',
            ram: '32',
            scratch: '100',
            partition: 'normal',
            ref: 'hg38',
            paired: 'true',
            strandMode: 'sense',
            featureLevel: 'gene',
            transcriptTypes: 'protein_coding,lncRNA',
            minReads: '10',
            normMethod: 'TMM',
            runGO: 'true',
            backgroundExpression: '5',
        });
    },
    async updateSize(datasetId: number): Promise<void> {
        return Promise.resolve();
    },
    async setBFabricId(datasetId: number, bfabricId: string): Promise<void> {
        return Promise.resolve();
    },
    async announceDataset(datasetId: number): Promise<void> {
        return Promise.resolve();
    },
    async geoUploader(datasetId: number): Promise<void> {
        return Promise.resolve();
    },
    async deleteDataset(datasetId: number): Promise<void> {
        return Promise.resolve();
    },
    async getResubmitData(datasetId: number): Promise<{ appName: string; parameters: Record<string, any> }> {
        // Different values from schema defaults to demonstrate resubmit prepopulation
        return Promise.resolve({
            appName: 'CountQC',
            parameters: {
                cores: 16,
                ram: 64,
                scratch: 200,
                partition: 'high',
                ref: 'mm10',
                paired: false,
                strandMode: 'antisense',
                featureLevel: 'transcript',
                transcriptTypes: 'protein_coding',
                minReads: 25,
                normMethod: 'RLE',
                runGO: false,
                backgroundExpression: 10,
            },
        });
    },
};
