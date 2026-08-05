'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { DatasetSample } from '@/lib/types';

interface DatasetSamplesProps {
  samples: DatasetSample[];
  projectNumber: number;
  datasetId: number;
  dataPaths: string[];
}

export default function DatasetSamples({ samples, projectNumber, datasetId, dataPaths }: DatasetSamplesProps) {
  const router = useRouter();

  // Check if any column has [Factor] postfix
  const hasFactorColumns = samples.length > 0 &&
    Array.from(new Set(samples.flatMap(sample => Object.keys(sample))))
      .some(col => col.endsWith('[Factor]'));

  // TODO: move this part of the code to when you load the dataset info, not in the dataset samples
//   if (isDatasetSamplesLoading && !datasetSamples) {
//     return (
//       <div className="animate-pulse">
//         <div className="bg-gray-200 rounded-lg">
//           <div className="px-4 py-3 bg-gray-100 border-b">
//             <div className="flex space-x-4">
//               <div className="h-4 bg-gray-300 rounded w-16"></div>
//               <div className="h-4 bg-gray-300 rounded w-24"></div>
//               <div className="h-4 bg-gray-300 rounded w-20"></div>
//               <div className="h-4 bg-gray-300 rounded w-32"></div>
//             </div>
//           </div>
//           {[...Array(3)].map((_, i) => (
//             <div key={i} className="px-4 py-3 border-b">
//               <div className="flex space-x-4">
//                 <div className="h-4 bg-gray-200 rounded w-12"></div>
//                 <div className="h-4 bg-gray-200 rounded w-20"></div>
//                 <div className="h-4 bg-gray-200 rounded w-16"></div>
//                 <div className="h-4 bg-gray-200 rounded w-28"></div>
//               </div>
//             </div>
//           ))}
//         </div>
//       </div>
//     );
//   }

  if (samples.length == 0) {
    return (
      <div className="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
        <div className="text-gray-400 text-lg mb-2">📊</div>
        <h4 className="text-lg font-medium text-gray-900 mb-2">No samples found</h4>
        <p className="text-gray-500 text-sm mb-4">This dataset doesn't contain any sample data yet.</p>
        <p className="text-gray-400 text-xs">Samples will appear here once they are added to the dataset.</p>
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold">Dataset Samples</h3>
        <div className="flex items-center gap-2">
          {/* Search field */}
          <input
            type="text"
            placeholder="Search samples..."
            className="px-3 py-1 text-sm border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          />

          {/* Action buttons */}
          {hasFactorColumns && (
            <Link
              href={`/projects/${projectNumber}/datasets/${datasetId}/factors/edit`}
              className="px-3 py-1 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors"
            >
              Edit Factors
            </Link>
          )}
          {dataPaths.length === 1 ? (
            <button
              className="px-3 py-1 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors"
              onClick={() => router.push(`/files/${dataPaths[0]}`)}
            >
              Data Folder
            </button>
          ) : dataPaths.length > 1 ? (
            <div className="relative group">
              <button className="px-3 py-1 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors">
                Data Folders ({dataPaths.length})
              </button>
              <div className="absolute top-full left-0 mt-1 bg-white border border-gray-200 rounded-md shadow-lg z-50 min-w-48 hidden group-hover:block">
                {dataPaths.map((path) => (
                  <button
                    key={path}
                    onClick={() => router.push(`/files/${path}`)}
                    className="block w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-100"
                  >
                    {path}
                  </button>
                ))}
              </div>
            </div>
          ) : null}
          <Link
            href={`/projects/${projectNumber}/datasets/${datasetId}/samples/edit`}
            className="px-3 py-1 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors"
          >
            Edit Table
          </Link>
        </div>
      </div>
      <div className="overflow-x-auto">
        <table className="min-w-full bg-white rounded-lg">
          <thead className="bg-brand-300 text-gray-800">
            <tr>
              {Array.from(new Set(samples.flatMap(sample => Object.keys(sample)))).map((column) => (
                <th key={column} className="px-3 py-2 text-left text-sm font-semibold max-w-[200px] truncate">
                  {column}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100 text-sm">
            {samples.map((sample: DatasetSample, index: number) => (
              <tr key={sample.Name} className="odd:bg-white even:bg-gray-50/50 hover:bg-brand-50 transition-colors">
                {Array.from(new Set(samples.flatMap(s => Object.keys(s)))).map((column) => {
                  const cellValue = sample[column] !== undefined ? String(sample[column]) : '-';
                  return (
                    <td
                      key={column}
                      className="px-3 py-2 text-gray-700 max-w-[200px] truncate cursor-default"
                      title={cellValue}
                    >
                      {cellValue}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
