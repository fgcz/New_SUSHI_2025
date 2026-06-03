import { DatasetFullResponse } from '@/lib/types';

interface DatasetInfoCardProps {
  dataset: DatasetFullResponse;
}

export default function DatasetInfoCard({ dataset }: DatasetInfoCardProps) {
  return (
    <div className="bg-white border rounded-lg overflow-hidden h-full">
      <div className="p-6 h-full">
        <h3 className="text-lg font-semibold mb-4">Dataset Information</h3>
        <div className="space-y-3 text-sm">
          <div className="flex">
            <span className="text-gray-600 mr-2">ID:</span>
            <span>{dataset.id}</span>
          </div>
          <div className="flex">
            <span className="text-gray-600 mr-2">Name:</span>
            <span>{dataset.name}</span>
          </div>
          <div className="flex">
            <span className="text-gray-600 mr-2">Project:</span>
            <span>{dataset.project_number}</span>
          </div>
          <div className="flex">
            <span className="text-gray-600 mr-2">Created:</span>
            <span>{new Date(dataset.created_at).toLocaleString()}</span>
          </div>
          <div className="flex">
            <span className="text-gray-600 mr-2">Created by:</span>
            <span>{dataset.user || 'N/A'}</span>
          </div>
          <div className="flex">
            <span className="text-gray-600 mr-2">App:</span>
            <span>{dataset.omics_app_name || 'N/A'}</span>
          </div>
          <div className="flex">
            <span className="text-gray-600 mr-2">Samples:</span>
            <span>{dataset.samples_count ?? 0}</span>
          </div>
          <div className="flex">
            <span className="text-gray-600 mr-2">BFabric ID:</span>
            <span>
              {dataset.bfabric_id ? (
                <a
                  href={`https://fgcz-bfabric.uzh.ch/bfabric/dataset/show.html?id=${dataset.bfabric_id}&tab=details`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-brand-600 hover:underline"
                >
                  {dataset.bfabric_id}
                </a>
              ) : 'N/A'}
            </span>
          </div>
          <div className="flex">
            <span className="text-gray-600 mr-2">Order ID:</span>
            <span>
              {dataset.order_ids && dataset.order_ids.length > 0
                ? dataset.order_ids.map(id => (
                    <a
                      key={id}
                      href={`https://fgcz-bfabric.uzh.ch/bfabric/order/show.html?id=${id}&tab=details`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-brand-600 hover:underline mr-2"
                    >
                      o{id}
                    </a>
                  ))
                : 'N/A'}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
