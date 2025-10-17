import Link from 'next/link';
import { DatasetSample } from '@/lib/types';
import { useDatasetSamples } from '@/lib/hooks';

interface DatasetSamplesProps {
  datasetId: number;
  projectNumber: number;
}

export default function DatasetSamples({ datasetId, projectNumber }: DatasetSamplesProps) {
  const { samples: datasetSamples, isLoading: isDatasetSamplesLoading, error: datasetSamplesError, isEmpty: isSamplesEmpty } = useDatasetSamples(datasetId);

  if (isDatasetSamplesLoading && !datasetSamples) {
    return (
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
    );
  }

  if (datasetSamplesError) {
    return (
      <div className="text-center py-8 bg-red-50 rounded-lg border border-red-200">
        <div className="text-red-600 font-medium mb-2">Failed to load samples</div>
        <p className="text-red-500 text-sm">There was an error loading the sample data for this dataset.</p>
      </div>
    );
  }

  if (!datasetSamples || isSamplesEmpty) {
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
        <h3 className="text-lg font-semibold">Samples</h3>
        <Link 
          href={`/projects/${projectNumber}/datasets/${datasetId}/samples/edit`}
          className="px-3 py-1 text-sm font-medium text-blue-700 bg-blue-100 rounded-md hover:bg-blue-200 transition-colors"
        >
          ✏️ Edit Table
        </Link>
      </div>
      <div className="overflow-x-auto">
        <table className="min-w-full bg-white border border-gray-200 rounded-lg">
          <thead className="bg-gray-50">
            <tr>
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
    </div>
  );
}