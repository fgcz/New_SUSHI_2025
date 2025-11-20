import { ProjectDataset } from '@/lib/types';

interface DatasetInfoCardProps {
  dataset: ProjectDataset;
}

export default function DatasetInfoCard({ dataset }: DatasetInfoCardProps) {
  return (
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
  );
}