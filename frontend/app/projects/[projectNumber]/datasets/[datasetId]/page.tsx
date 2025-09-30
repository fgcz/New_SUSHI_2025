'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { projectApi, datasetApi } from '@/lib/api';
import { DatasetRunnableApp, DatasetSample } from '@/lib/types';
import dynamic from 'next/dynamic';

const TreeComponent = dynamic(() => import('./TreeComponent'), {
  ssr: false,
  loading: () => (
    <div className="min-h-[120px] animate-pulse space-y-2">
      <div className="flex items-center space-x-2">
        <div className="h-4 w-4 bg-gray-300 rounded"></div>
        <div className="h-4 bg-gray-300 rounded w-32"></div>
      </div>
      <div className="flex items-center space-x-2 ml-6">
        <div className="h-4 w-4 bg-gray-300 rounded"></div>
        <div className="h-4 bg-gray-300 rounded w-28"></div>
      </div>
      <div className="flex items-center space-x-2 ml-12">
        <div className="h-4 w-4 bg-gray-300 rounded"></div>
        <div className="h-4 bg-gray-300 rounded w-24"></div>
      </div>
      <div className="flex items-center space-x-2 ml-12">
        <div className="h-4 w-4 bg-gray-300 rounded"></div>
        <div className="h-4 bg-gray-300 rounded w-36"></div>
      </div>
    </div>
  )
});

export default function DatasetDetailPage() {
  const params = useParams<{ projectNumber: string; datasetId: string }>();
  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);

  const { data, isLoading: isDatasetLoading, error: datasetError } = useQuery({
    queryKey: ['datasets', projectNumber],
    queryFn: () => projectApi.getProjectDatasets(projectNumber),
    staleTime: 60_000,
  });

  const { data: runnableApps, isLoading: isRunnableAppsLoading, error: runnableAppsError } = useQuery({
    queryKey: ['runnableApps', datasetId],
    queryFn: () => datasetApi.getRunnableApps(datasetId),
    staleTime: 60_000,
  });

  const { data: datasetTree, isLoading: isDatasetTreeLoading, error: datasetTreeError } = useQuery({
    queryKey: ['datasetTree', datasetId],
    queryFn: () => datasetApi.getDatasetTree(datasetId),
    staleTime: 60_000,
  });

  const { data: datasetSamples, isLoading: isDatasetSamplesLoading, error: datasetSamplesError } = useQuery({
    queryKey: ['datasetSamples', datasetId],
    queryFn: () => datasetApi.getDatasetSamples(datasetId),
    staleTime: 60_000,
  });

  const handleAppClick = (category: string, app: string) => {
    console.log(`Running ${app} from ${category} category for dataset ${datasetId}`);
  };

  if (isDatasetLoading) return (
    <div className="container mx-auto px-6 py-8">
      <div className="animate-pulse">
        {/* Breadcrumb skeleton */}
        <div className="h-4 bg-gray-200 rounded w-48 mb-6"></div>
        
        {/* Title skeleton */}
        <div className="h-8 bg-gray-200 rounded w-64 mb-6"></div>
        
        {/* Card skeleton */}
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
      </div>
    </div>
  );
  
  if (datasetError) return (
    <div className="container mx-auto px-6 py-8">
      <div className="text-center py-12">
        <div className="text-red-600 text-lg font-medium mb-2">Failed to load dataset</div>
        <p className="text-gray-500 mb-4">There was an error loading the dataset information.</p>
        <Link href={`/projects/${projectNumber}/datasets`} className="text-blue-600 hover:underline">
          ← Back to Datasets
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
      {/* Improved breadcrumb navigation */}
      <nav className="mb-6" aria-label="Breadcrumb">
        <ol className="flex items-center space-x-2 text-sm text-gray-500">
          <li>
            <Link href="/projects" className="hover:text-gray-700">Projects</Link>
          </li>
          <li>/</li>
          <li>
            <Link href={`/projects/${projectNumber}`} className="hover:text-gray-700">Project {projectNumber}</Link>
          </li>
          <li>/</li>
          <li>
            <Link href={`/projects/${projectNumber}/datasets`} className="hover:text-gray-700">Datasets</Link>
          </li>
          <li>/</li>
          <li className="text-gray-900 font-medium" aria-current="page">{dataset.name}</li>
        </ol>
      </nav>

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Dataset Details - {dataset.name}</h1>
        <Link 
          href={`/projects/${projectNumber}/datasets`} 
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          ← Back to Datasets
        </Link>
      </div>

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

          <div className="mt-8 pt-6 border-t">
            <h3 className="text-lg font-semibold mb-4">Folder Structure</h3>
            {isDatasetTreeLoading && !datasetTree ? (
              <div className="min-h-[120px] animate-pulse space-y-2">
                <div className="flex items-center space-x-2">
                  <div className="h-4 w-4 bg-gray-300 rounded"></div>
                  <div className="h-4 bg-gray-300 rounded w-32"></div>
                </div>
                <div className="flex items-center space-x-2 ml-6">
                  <div className="h-4 w-4 bg-gray-300 rounded"></div>
                  <div className="h-4 bg-gray-300 rounded w-28"></div>
                </div>
                <div className="flex items-center space-x-2 ml-12">
                  <div className="h-4 w-4 bg-gray-300 rounded"></div>
                  <div className="h-4 bg-gray-300 rounded w-24"></div>
                </div>
                <div className="flex items-center space-x-2 ml-12">
                  <div className="h-4 w-4 bg-gray-300 rounded"></div>
                  <div className="h-4 bg-gray-300 rounded w-36"></div>
                </div>
              </div>
            ) : datasetTreeError ? (
              <div className="text-center py-8 bg-red-50 rounded-lg border border-red-200">
                <div className="text-red-600 font-medium mb-2">Failed to load folder structure</div>
                <p className="text-red-500 text-sm">There was an error loading the folder tree for this dataset.</p>
              </div>
            ) : datasetTree ? (
              <div className="min-h-[120px]">
                <TreeComponent datasetTree={datasetTree} datasetId={datasetId} projectNumber={projectNumber} />
              </div>
            ) : (
              <div className="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
                <div className="text-gray-400 text-lg mb-2">📁</div>
                <h4 className="text-lg font-medium text-gray-900 mb-2">No folder structure found</h4>
                <p className="text-gray-500 text-sm mb-4">This dataset doesn't have any folder structure defined.</p>
                <p className="text-gray-400 text-xs">Folder navigation will appear here once the structure is created.</p>
              </div>
            )}
          </div>

          <div className="mt-8 pt-6 border-t">
            <h3 className="text-lg font-semibold mb-4">Samples</h3>
            {isDatasetSamplesLoading && !datasetSamples ? (
              <div className="animate-pulse">
                <div className="bg-gray-200 rounded-lg">
                  <div className="px-4 py-3 bg-gray-100 border-b">
                    <div className="flex space-x-4">
                      <div className="h-4 bg-gray-300 rounded w-16"></div>
                      <div className="h-4 bg-gray-300 rounded w-24"></div>
                      <div className="h-4 bg-gray-300 rounded w-20"></div>
                      <div className="h-4 bg-gray-300 rounded w-32"></div>
                    </div>
                  </div>
                  {[...Array(3)].map((_, i) => (
                    <div key={i} className="px-4 py-3 border-b">
                      <div className="flex space-x-4">
                        <div className="h-4 bg-gray-200 rounded w-12"></div>
                        <div className="h-4 bg-gray-200 rounded w-20"></div>
                        <div className="h-4 bg-gray-200 rounded w-16"></div>
                        <div className="h-4 bg-gray-200 rounded w-28"></div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ) : datasetSamplesError ? (
              <div className="text-center py-8 bg-red-50 rounded-lg border border-red-200">
                <div className="text-red-600 font-medium mb-2">Failed to load samples</div>
                <p className="text-red-500 text-sm">There was an error loading the sample data for this dataset.</p>
              </div>
            ) : datasetSamples && datasetSamples.length > 0 ? (
              <div className="overflow-x-auto">
                <table className="min-w-full bg-white border border-gray-200 rounded-lg">
                  <thead className="bg-gray-50">
                    <tr>
                      {/* Get all unique column names from all samples */}
                      {Array.from(new Set(datasetSamples.flatMap(sample => Object.keys(sample)))).map((column) => (
                        <th key={column} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-b">
                          {column}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-200">
                    {datasetSamples.map((sample: DatasetSample, index: number) => (
                      <tr key={sample.id} className={index % 2 === 0 ? 'bg-white' : 'bg-gray-50'}>
                        {Array.from(new Set(datasetSamples.flatMap(s => Object.keys(s)))).map((column) => (
                          <td key={column} className="px-4 py-3 text-sm text-gray-900 border-b">
                            {sample[column] !== undefined ? String(sample[column]) : '-'}
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
                <div className="text-gray-400 text-lg mb-2">📊</div>
                <h4 className="text-lg font-medium text-gray-900 mb-2">No samples found</h4>
                <p className="text-gray-500 text-sm mb-4">This dataset doesn't contain any sample data yet.</p>
                <p className="text-gray-400 text-xs">Samples will appear here once they are added to the dataset.</p>
              </div>
            )}
          </div>

          <div className="mt-8 pt-6 border-t">
            <h3 className="text-lg font-semibold mb-4">Runnable Applications</h3>
            {isRunnableAppsLoading && !runnableApps ? (
              <div className="animate-pulse space-y-4">
                <div className="bg-gray-200 rounded-lg p-4">
                  <div className="h-5 bg-gray-300 rounded w-24 mb-3"></div>
                  <div className="flex space-x-2">
                    <div className="h-8 bg-gray-300 rounded w-20"></div>
                    <div className="h-8 bg-gray-300 rounded w-16"></div>
                    <div className="h-8 bg-gray-300 rounded w-18"></div>
                  </div>
                </div>
                <div className="bg-gray-200 rounded-lg p-4">
                  <div className="h-5 bg-gray-300 rounded w-20 mb-3"></div>
                  <div className="flex space-x-2">
                    <div className="h-8 bg-gray-300 rounded w-16"></div>
                    <div className="h-8 bg-gray-300 rounded w-12"></div>
                    <div className="h-8 bg-gray-300 rounded w-14"></div>
                  </div>
                </div>
              </div>
            ) : runnableAppsError ? (
              <div className="text-center py-8 bg-red-50 rounded-lg border border-red-200">
                <div className="text-red-600 font-medium mb-2">Failed to load runnable applications</div>
                <p className="text-red-500 text-sm">There was an error loading the available applications for this dataset.</p>
              </div>
            ) : runnableApps && runnableApps.length > 0 ? (
              <div className="space-y-6">
                {runnableApps.map((category: DatasetRunnableApp, index: number) => (
                  <div key={index} className="bg-gray-50 rounded-lg p-4">
                    <h4 className="text-md font-medium mb-3 text-gray-800 capitalize">
                      {category.category}
                    </h4>
                    <div className="flex flex-wrap gap-2">
                      {category.applications.map((app: string) => (
                        <button
                          key={app}
                          onClick={() => handleAppClick(category.category, app)}
                          className="px-3 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors duration-200 text-sm font-medium"
                        >
                          {app}
                        </button>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
                <div className="text-gray-400 text-lg mb-2">⚙️</div>
                <h4 className="text-lg font-medium text-gray-900 mb-2">No runnable applications found</h4>
                <p className="text-gray-500 text-sm mb-4">There are no applications available to run on this dataset.</p>
                <p className="text-gray-400 text-xs">Available applications will appear here based on the dataset type and configuration.</p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}


