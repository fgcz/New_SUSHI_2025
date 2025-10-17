'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { projectApi, datasetApi } from '@/lib/api';
import EditableTable from './EditableTable';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';

export default function SamplesEditPage() {
  const params = useParams<{ projectNumber: string; datasetId: string }>();
  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);

  const { data, isLoading: isDatasetLoading, error: datasetError } = useQuery({
    queryKey: ['datasets', projectNumber],
    queryFn: () => projectApi.getProjectDatasets(projectNumber),
    staleTime: 60_000,
  });

  const { data: datasetSamples, isLoading: isDatasetSamplesLoading, error: datasetSamplesError } = useQuery({
    queryKey: ['datasetSamples', datasetId],
    queryFn: () => datasetApi.getDatasetSamples(datasetId),
    staleTime: 60_000,
  });

  if (isDatasetLoading) return (
    <div className="container mx-auto px-6 py-8">
      <div className="animate-pulse">
        {/* Breadcrumb skeleton */}
        <div className="h-4 bg-gray-200 rounded w-48 mb-6"></div>
        
        {/* Title skeleton */}
        <div className="flex items-center justify-between mb-6">
          <div className="h-8 bg-gray-200 rounded w-64"></div>
          <div className="h-8 bg-gray-200 rounded w-32"></div>
        </div>

        <div className="space-y-6">
          {/* Dataset Details skeleton */}
          <div className="bg-white border rounded-lg overflow-hidden">
            <div className="p-6 space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="space-y-3">
                  <div className="h-6 bg-gray-200 rounded w-32 mb-4"></div>
                  {[...Array(5)].map((_, i) => (
                    <div key={i} className="flex justify-between">
                      <div className="h-4 bg-gray-200 rounded w-20"></div>
                      <div className="h-4 bg-gray-200 rounded w-24"></div>
                    </div>
                  ))}
                </div>
                <div className="space-y-3">
                  <div className="h-6 bg-gray-200 rounded w-40 mb-4"></div>
                  {[...Array(3)].map((_, i) => (
                    <div key={i} className="flex justify-between">
                      <div className="h-4 bg-gray-200 rounded w-24"></div>
                      <div className="h-4 bg-gray-200 rounded w-16"></div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>

          {/* Samples Edit skeleton */}
          <div className="bg-white border rounded-lg overflow-hidden">
            <div className="px-6 py-4 bg-gray-50 border-b">
              <div className="h-6 bg-gray-200 rounded w-40 mb-2"></div>
              <div className="h-4 bg-gray-200 rounded w-56"></div>
            </div>
            <div className="p-6">
              <div className="overflow-x-auto">
                <div className="bg-gray-200 rounded-lg">
                  <div className="px-4 py-3 bg-gray-100 border-b">
                    <div className="flex space-x-4">
                      <div className="h-4 bg-gray-300 rounded w-16"></div>
                      <div className="h-4 bg-gray-300 rounded w-24"></div>
                      <div className="h-4 bg-gray-300 rounded w-20"></div>
                      <div className="h-4 bg-gray-300 rounded w-32"></div>
                      <div className="h-4 bg-gray-300 rounded w-16"></div>
                    </div>
                  </div>
                  {[...Array(3)].map((_, i) => (
                    <div key={i} className="px-4 py-3 border-b">
                      <div className="flex space-x-4">
                        <div className="h-8 bg-gray-200 rounded w-16"></div>
                        <div className="h-8 bg-gray-200 rounded w-24"></div>
                        <div className="h-8 bg-gray-200 rounded w-20"></div>
                        <div className="h-8 bg-gray-200 rounded w-32"></div>
                        <div className="h-6 bg-gray-200 rounded w-12"></div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
              
              {/* Action buttons skeleton */}
              <div className="mt-4 flex justify-end items-center space-x-2">
                <div className="h-8 bg-gray-200 rounded w-16"></div>
                <div className="h-8 bg-gray-200 rounded w-24"></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
  
  if (datasetError) return (
    <div className="container mx-auto px-6 py-8">
      <div className="text-center py-12">
        <div className="text-red-600 text-lg font-medium mb-2">Failed to load dataset</div>
        <p className="text-gray-500 mb-4">There was an error loading the dataset information.</p>
        <Link href={`/projects/${projectNumber}/datasets/${datasetId}`} className="text-blue-600 hover:underline">
          ← Back to Dataset
        </Link>
      </div>
    </div>
  );

  const dataset = data?.datasets?.find(ds => ds.id === datasetId);

  if (!dataset) {
    return (
      <div className="container mx-auto px-6 py-8">
        <h1 className="text-2xl font-bold mb-4 text-red-600">Dataset Not Found</h1>
        <p className="text-gray-700 mb-6">Dataset {datasetId} was not found in project {projectNumber}.</p>
        <Link href={`/projects/${projectNumber}/datasets`} className="text-blue-600 hover:underline">← Back to Datasets</Link>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-6 py-8">

      <Breadcrumbs items={[
        { label: 'Projects', href: '/projects' },
        { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
        { label: 'Datasets', href: `/projects/${projectNumber}/datasets` },
        { label: dataset.name, href: `/projects/${projectNumber}/datasets/${datasetId}`},
        { label: "Edit Samples", active: true }
      ]} />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Edit Samples - {dataset.name}</h1>
        <Link 
          href={`/projects/${projectNumber}/datasets/${datasetId}`} 
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          ← Back to Dataset
        </Link>
      </div>

      <div className="space-y-6">
        {/* Dataset Details Section - Read Only (Same as original view) */}
        <div className="bg-white border rounded-lg overflow-hidden">
          <div className="p-6 space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <h3 className="text-lg font-semibold mb-4">Basic Information</h3>
                <div className="space-y-3">
                  <div className="flex justify-between">
                    <span className="font-medium text-gray-600">ID:</span>
                    <span>{dataset.id}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="font-medium text-gray-600">Name:</span>
                    <span>{dataset.name}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="font-medium text-gray-600">Project:</span>
                    <span>{dataset.project_number}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="font-medium text-gray-600">Created:</span>
                    <span>{new Date(dataset.created_at).toLocaleString()}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="font-medium text-gray-600">Created by:</span>
                    <span>{dataset.user_login || 'N/A'}</span>
                  </div>
                </div>
              </div>

              <div>
                <h3 className="text-lg font-semibold mb-4">Application & Samples</h3>
                <div className="space-y-3">
                  <div className="flex justify-between">
                    <span className="font-medium text-gray-600">SushiApp:</span>
                    <span>{dataset.sushi_app_name || 'N/A'}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="font-medium text-gray-600">Samples:</span>
                    <span>{dataset.completed_samples ?? 0} / {dataset.samples_length ?? 0}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="font-medium text-gray-600">BFabric ID:</span>
                    <span>
                      {dataset.bfabric_id ? (
                        <a
                          href={`https://fgcz-bfabric.uzh.ch/bfabric/dataset/show.html?id=${dataset.bfabric_id}&tab=details`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-blue-600 hover:underline"
                        >
                          {dataset.bfabric_id}
                        </a>
                      ) : 'N/A'}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Editable Samples Section */}
        <div className="bg-white border rounded-lg overflow-hidden">
          <div className="px-6 py-4 bg-gray-50 border-b">
            <h2 className="text-lg font-semibold">Edit Samples Table</h2>
            <p className="text-sm text-gray-600 mt-1">
              Edit sample data directly in the table below
            </p>
          </div>
          <div className="p-6">
            <EditableTable
              initialSamples={datasetSamples || []}
              projectNumber={projectNumber}
              datasetId={datasetId}
              isLoading={isDatasetSamplesLoading}
              error={datasetSamplesError}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
