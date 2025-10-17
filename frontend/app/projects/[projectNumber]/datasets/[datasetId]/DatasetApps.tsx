import Link from 'next/link';
import { DatasetRunnableApp } from '@/lib/types';
import { useDatasetApps } from '@/lib/hooks';

interface DatasetAppsProps {
  datasetId: number;
  projectNumber: number;
}

export default function DatasetApps({ datasetId, projectNumber }: DatasetAppsProps) {
  const { apps: runnableApps, isLoading: isRunnableAppsLoading, error: runnableAppsError, isEmpty: isAppsEmpty } = useDatasetApps(datasetId);

  if (isRunnableAppsLoading && !runnableApps) {
    return (
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
    );
  }

  if (runnableAppsError) {
    return (
      <div className="text-center py-8 bg-red-50 rounded-lg border border-red-200">
        <div className="text-red-600 font-medium mb-2">Failed to load runnable applications</div>
        <p className="text-red-500 text-sm">There was an error loading the available applications for this dataset.</p>
      </div>
    );
  }

  if (!runnableApps || isAppsEmpty) {
    return (
      <div className="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
        <div className="text-gray-400 text-lg mb-2">⚙️</div>
        <h4 className="text-lg font-medium text-gray-900 mb-2">No runnable applications found</h4>
        <p className="text-gray-500 text-sm mb-4">There are no applications available to run on this dataset.</p>
        <p className="text-gray-400 text-xs">Available applications will appear here based on the dataset type and configuration.</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {runnableApps.map((category: DatasetRunnableApp, index: number) => (
        <div key={index} className="bg-gray-50 rounded-lg p-4">
          <h4 className="text-md font-medium mb-3 text-gray-800 capitalize">
            {category.category}
          </h4>
          <div className="flex flex-wrap gap-2">
            {category.applications.map((app: string) => (
              <Link
                key={app}
                href={`/projects/${projectNumber}/datasets/${datasetId}/run-application/${app}`}
                className="px-3 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors duration-200 text-sm font-medium"
              >
                {app}
              </Link>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}