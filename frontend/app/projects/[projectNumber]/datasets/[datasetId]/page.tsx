'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { projectApi } from '@/lib/api';

export default function DatasetDetailPage() {
  const params = useParams<{ projectNumber: string; datasetId: string }>();
  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);

  const { data, isLoading, error } = useQuery({
    queryKey: ['datasets', projectNumber],
    queryFn: () => projectApi.getProjectDatasets(projectNumber),
    staleTime: 60_000,
  });

  if (isLoading) return <div className="container mx-auto px-6 py-8">Loading dataset...</div>;
  if (error) return <div className="container mx-auto px-6 py-8 text-red-600">Failed to load dataset</div>;

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
      <div className="mb-6">
        <Link href={`/projects/${projectNumber}/datasets`} className="text-blue-600 hover:underline">← Back to Datasets</Link>
      </div>

      <h1 className="text-2xl font-bold mb-6">Dataset Details - {dataset.name}</h1>

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

          {(dataset.parent_id || (dataset.children_ids && dataset.children_ids.length > 0)) && (
            <div className="mt-8 pt-6 border-t">
              <h3 className="text-lg font-semibold mb-4">Relationships</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {dataset.parent_id && (
                  <div>
                    <span className="font-medium text-gray-600">Parent Dataset:</span>
                    <div className="mt-2">
                      <Link
                        href={`/projects/${projectNumber}/datasets/${dataset.parent_id}`}
                        className="text-blue-600 hover:underline"
                      >
                        Dataset {dataset.parent_id}
                      </Link>
                    </div>
                  </div>
                )}
                
                {dataset.children_ids && dataset.children_ids.length > 0 && (
                  <div>
                    <span className="font-medium text-gray-600">Child Datasets:</span>
                    <div className="mt-2 space-y-1">
                      {dataset.children_ids.map((childId) => (
                        <div key={childId}>
                          <Link
                            href={`/projects/${projectNumber}/datasets/${childId}`}
                            className="text-blue-600 hover:underline"
                          >
                            Dataset {childId}
                          </Link>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}


