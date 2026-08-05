import Link from 'next/link';
import { DatasetAppCategory } from '@/lib/types';

interface DatasetAppsProps {
  runnableApps: DatasetAppCategory[];
  datasetId: number;
  projectNumber: number;
}

export default function DatasetApps({runnableApps, datasetId, projectNumber }: DatasetAppsProps) {
  // TODO: Move this to when loading the datasetInfo
  // if (isRunnableAppsLoading && !runnableApps) {
  //   return (
  //     <div className="animate-pulse space-y-4">
  //       <div className="bg-gray-200 rounded-lg p-4">
  //         <div className="h-5 bg-gray-300 rounded w-24 mb-3"></div>
  //         <div className="flex space-x-2">
  //           <div className="h-8 bg-gray-300 rounded w-20"></div>
  //           <div className="h-8 bg-gray-300 rounded w-16"></div>
  //           <div className="h-8 bg-gray-300 rounded w-18"></div>
  //         </div>
  //       </div>
  //       <div className="bg-gray-200 rounded-lg p-4">
  //         <div className="h-5 bg-gray-300 rounded w-20 mb-3"></div>
  //         <div className="flex space-x-2">
  //           <div className="h-8 bg-gray-300 rounded w-16"></div>
  //           <div className="h-8 bg-gray-300 rounded w-12"></div>
  //           <div className="h-8 bg-gray-300 rounded w-14"></div>
  //         </div>
  //       </div>
  //     </div>
  //   );
  // }

  if (runnableApps.length == 0) {
    return <p className="text-sm text-gray-400">No applications available for this dataset.</p>;
  }

  return (
    <div className="bg-gray-50 rounded-lg p-4">
      <div className="space-y-4">
        {runnableApps.map((category: DatasetAppCategory, index: number) => (
          <div key={index} className="flex items-center mb-3" style={{ gap: '1rem' }}>
            <h4 className="text-md font-medium text-gray-800 capitalize whitespace-nowrap">
              {category.category}
            </h4>
            <div className="flex overflow-x-auto gap-1">
              {category.apps.map((app) => (
                <Link
                  key={app.name}
                  href={`/projects/${projectNumber}/datasets/${datasetId}/run-application/${app.name}`}
                  className="px-3 py-1.5 text-white rounded text-sm font-medium whitespace-nowrap bg-brand-600 hover:bg-brand-700 transition-colors"
                >
                  {app.name}
                </Link>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
