import { useEffect } from 'react';
import Link from 'next/link';
import { DatasetSample } from '@/lib/types';
import { useEditableSamples } from './useEditableSamples';

interface EditableTableProps {
  initialSamples: DatasetSample[];
  projectNumber: number;
  datasetId: number;
  isLoading?: boolean;
  error?: Error | null;
}

export default function EditableTable({ 
  initialSamples, 
  projectNumber, 
  datasetId, 
  isLoading = false, 
  error = null 
}: EditableTableProps) {
  const {
    editableSamples,
    editableColumns,
    newColumnName,
    setNewColumnName,
    initializeData,
    updateCell,
    removeRow,
    removeColumn,
    addColumn,
    renameColumn
  } = useEditableSamples();

  // Initialize data when samples are loaded
  useEffect(() => {
    if (initialSamples.length > 0 && editableSamples.length === 0) {
      initializeData(initialSamples);
    }
  }, [initialSamples, editableSamples.length, initializeData]);

  if (isLoading && !initialSamples.length) {
    return (
      <div className="animate-pulse">
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
        
        {/* Action buttons skeleton */}
        <div className="mt-4 flex justify-end items-center space-x-2">
          <div className="h-8 bg-gray-200 rounded w-16"></div>
          <div className="h-8 bg-gray-200 rounded w-24"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-center py-8 bg-red-50 rounded-lg border border-red-200">
        <div className="text-red-600 font-medium mb-2">Failed to load samples</div>
        <p className="text-red-500 text-sm">There was an error loading the sample data for this dataset.</p>
      </div>
    );
  }

  if (!initialSamples.length) {
    return (
      <div className="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
        <div className="text-gray-400 text-lg mb-2">📊</div>
        <h4 className="text-lg font-medium text-gray-900 mb-2">No samples found</h4>
        <p className="text-gray-500 text-sm mb-4">This dataset doesn't contain any sample data yet.</p>
        <p className="text-gray-400 text-sm">No samples available to edit.</p>
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full bg-white border border-gray-200 rounded-lg">
        <thead className="bg-gray-50">
          <tr>
            {editableColumns.map((column, colIndex) => (
              <th key={column} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-b relative">
                <div className="flex items-center justify-between">
                  <input 
                    type="text" 
                    value={column}
                    onChange={(e) => renameColumn(colIndex, e.target.value)}
                    className="bg-transparent border-none text-xs font-medium text-gray-500 uppercase tracking-wider w-full focus:outline-none focus:bg-white focus:text-gray-900 px-1 py-1 rounded"
                  />
                  <button 
                    onClick={() => removeColumn(colIndex)}
                    className="ml-2 text-red-600 hover:text-red-800 text-xs"
                    title="Remove column"
                  >
                    ×
                  </button>
                </div>
              </th>
            ))}
            <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider border-b">
              <div className="flex items-center justify-center space-x-2">
                <input 
                  type="text" 
                  value={newColumnName}
                  onChange={(e) => setNewColumnName(e.target.value)}
                  placeholder="New column"
                  className="text-xs px-2 py-1 border border-gray-300 rounded w-20"
                />
                <button 
                  onClick={addColumn}
                  className="px-2 py-1 text-xs text-blue-600 hover:text-blue-800"
                  title="Add column"
                >
                  +
                </button>
              </div>
              <div className="text-xs text-gray-400 mt-1">Actions</div>
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-200">
          {editableSamples.map((sample: DatasetSample, rowIndex: number) => (
            <tr key={sample.id} className={rowIndex % 2 === 0 ? 'bg-white' : 'bg-gray-50'}>
              {editableColumns.map((column) => (
                <td key={column} className="px-4 py-3 text-sm border-b">
                  <input 
                    type="text" 
                    value={sample[column] !== undefined ? String(sample[column]) : ''} 
                    onChange={(e) => updateCell(rowIndex, column, e.target.value)}
                    className="w-full px-2 py-1 border border-gray-300 rounded text-sm focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                  />
                </td>
              ))}
              <td className="px-4 py-3 text-center border-b">
                <button 
                  onClick={() => removeRow(rowIndex)}
                  className="px-2 py-1 text-xs text-red-600 hover:text-red-800"
                  title="Remove row"
                >
                  Delete Row
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      
      <div className="mt-4 flex justify-end items-center space-x-2">
        <Link
          href={`/projects/${projectNumber}/datasets/${datasetId}`}
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          Cancel
        </Link>
        <button className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700">
          Save Changes
        </button>
      </div>
    </div>
  );
}