import dynamic from 'next/dynamic';
import { useDatasetTree } from '@/lib/hooks';

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

interface DatasetTreeProps {
  datasetId: number;
  projectNumber: number;
}

export default function DatasetTree({ datasetId, projectNumber }: DatasetTreeProps) {
  const { datasetTree, isLoading: isDatasetTreeLoading, error: datasetTreeError, isEmpty: isTreeEmpty } = useDatasetTree(datasetId);

  if (isDatasetTreeLoading && !datasetTree) {
    return (
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
    );
  }

  if (datasetTreeError) {
    return (
      <div className="text-center py-8 bg-red-50 rounded-lg border border-red-200">
        <div className="text-red-600 font-medium mb-2">Failed to load folder structure</div>
        <p className="text-red-500 text-sm">There was an error loading the folder tree for this dataset.</p>
      </div>
    );
  }

  if (!datasetTree || isTreeEmpty) {
    return (
      <div className="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
        <div className="text-gray-400 text-lg mb-2">📁</div>
        <h4 className="text-lg font-medium text-gray-900 mb-2">No folder structure found</h4>
        <p className="text-gray-500 text-sm mb-4">This dataset doesn't have any folder structure defined.</p>
        <p className="text-gray-400 text-xs">Folder navigation will appear here once the structure is created.</p>
      </div>
    );
  }

  return (
    <div className="min-h-[120px]">
      <TreeComponent datasetTree={datasetTree} datasetId={datasetId} projectNumber={projectNumber} />
    </div>
  );
}