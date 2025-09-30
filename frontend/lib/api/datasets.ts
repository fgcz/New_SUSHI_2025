import { httpClient } from './client';
import { DatasetsResponse, DatasetResponse, CreateDatasetResponse, DatasetSamplesResponse, DatasetRunnableAppsResponse, DatasetTreeResponse} from '../types/dataset';

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

    async getDatasetTree(id: number): Promise<DatasetTreeResponse> {
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


    async getDatasetSamples(id: number): Promise<DatasetSamplesResponse> {
        return new Promise((resolve) => {
            setTimeout(() => {
                resolve([
                    {
                        id: 2011,
                        name: "Sample1",
                        "Condition [Factor]": "Diff",
                        "Species": "Homo sapiens",
                        "Order Id [B-Fabric]": 5444,
                        "RawDataDir [File]": "path/to/tar.tar",
                    },
                    {
                        id: 2012,
                        name: "Sample2",
                        "Condition [Factor]": "Undiff",
                        "Species": "Homo sapiens",
                        "Order Id [B-Fabric]": 5495,
                        "RawDataDir [File]": "path/to/tar.tar",
                    },
                ])
            }, 1000);
        });
    },

    async getRunnableApps(id: number): Promise<DatasetRunnableAppsResponse> {
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
            }, 1500);
        });
    },
};
