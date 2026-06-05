'use client';

import { useParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { projectApi } from '@/lib/api';
import { useImportDatasetForm } from '@/lib/hooks';
import ParentSelector from './ParentSelector';

export default function ImportDatasetPage() {
  const params = useParams<{ projectNumber: string }>();
  const projectNumber = Number(params.projectNumber);

  // Fetch tree data for parent selection
  const { data: treeData, isLoading: isTreeLoading } = useQuery({
    queryKey: ['datasets-tree', projectNumber],
    queryFn: () => projectApi.getProjectDatasetsTree(projectNumber),
    staleTime: 60_000,
  });

  // Form state and handlers
  const {
    file,
    datasetName,
    setDatasetName,
    parentId,
    parentIdInput,
    parentIdError,
    noParent,
    treeSearch,
    setTreeSearch,
    isSubmitting,
    error,
    isDragOver,
    handleFileChange,
    handleDragOver,
    handleDragLeave,
    handleDrop,
    handleParentIdChange,
    handleTreeSelect,
    handleNoParentChange,
    handleSubmit,
  } = useImportDatasetForm({ projectNumber, treeData });

  return (
    <div className="min-h-screen bg-gray-50 py-8">
      <div className="container mx-auto px-6 max-w-4xl">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-2xl font-semibold text-gray-900">Import Dataset</h1>
          <p className="text-gray-500 mt-1">
            Import a new dataset into project {projectNumber}
          </p>
        </div>

        {/* Form Card */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
          <form onSubmit={handleSubmit} className="space-y-5">
            {/* File selection */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1.5">
                Dataset File
              </label>
              <div
                className={`relative border-2 border-dashed rounded-lg p-4 text-center transition-colors ${
                  file
                    ? 'border-green-300 bg-green-50'
                    : isDragOver
                      ? 'border-brand-400 bg-brand-50'
                      : 'border-gray-300 hover:border-gray-400'
                }`}
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
              >
                <input
                  type="file"
                  accept=".txt,.csv,.tsv"
                  onChange={handleFileChange}
                  className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                />
                {file ? (
                  <div className="flex items-center justify-center gap-2">
                    <svg className="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <span className="text-sm text-gray-700">{file.name}</span>
                    <span className="text-xs text-gray-400">({(file.size / 1024).toFixed(1)} KB)</span>
                  </div>
                ) : (
                  <div>
                    <svg className="w-8 h-8 text-gray-400 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
                    </svg>
                    <p className="text-sm text-gray-600">
                      {isDragOver
                        ? 'Drop the file here'
                        : <>Click or drag to upload a <span className="font-medium">.txt</span>, <span className="font-medium">.csv</span>, or <span className="font-medium">.tsv</span> file</>
                      }
                    </p>
                  </div>
                )}
              </div>
            </div>

            {/* Dataset name and Parent dataset side by side */}
            <div className="grid grid-cols-2 gap-6">
              {/* Dataset name */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">
                  Dataset Name
                </label>
                <input
                  type="text"
                  value={datasetName}
                  onChange={(e) => setDatasetName(e.target.value)}
                  placeholder="Enter dataset name"
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent transition-shadow"
                />
              </div>

              {/* Parent dataset ID */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1.5">
                  Parent Dataset ID
                </label>
                <div className="flex gap-3">
                  <div className="flex-1">
                    <input
                      type="text"
                      value={noParent ? '' : parentIdInput}
                      onChange={(e) => handleParentIdChange(e.target.value)}
                      disabled={noParent}
                      placeholder="Enter ID or select below"
                      className={`w-full px-3 py-2 border rounded-lg text-sm transition-shadow ${
                        noParent
                          ? 'border-gray-200 bg-gray-50 text-gray-400'
                          : parentIdError
                            ? 'border-red-300 focus:ring-red-500 focus:ring-2 focus:outline-none'
                            : 'border-gray-300 focus:ring-brand-500 focus:ring-2 focus:outline-none'
                      }`}
                    />
                    {parentIdError && !noParent && (
                      <p className="text-xs text-red-500 mt-1">{parentIdError}</p>
                    )}
                  </div>
                  <label className="flex items-center gap-2 cursor-pointer select-none">
                    <input
                      type="checkbox"
                      checked={noParent}
                      onChange={(e) => handleNoParentChange(e.target.checked)}
                      className="w-4 h-4 rounded border-gray-300 text-brand-600 focus:ring-brand-500"
                    />
                    <span className="text-sm text-gray-600 whitespace-nowrap">No parent</span>
                  </label>
                </div>
              </div>
            </div>

            {/* Tree selector */}
            {!noParent && (
              <div className="space-y-2">
                <label className="block text-sm font-medium text-gray-700">
                  Select Parent Dataset
                </label>
                <div className="relative">
                  <svg className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                  </svg>
                  <input
                    type="text"
                    value={treeSearch}
                    onChange={(e) => setTreeSearch(e.target.value)}
                    placeholder="Search datasets..."
                    className="w-full pl-8 pr-3 py-1.5 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 bg-white"
                  />
                </div>

                {isTreeLoading ? (
                  <div className="border border-gray-200 rounded-lg p-6 text-center">
                    <div className="animate-spin w-5 h-5 border-2 border-gray-300 border-t-brand-600 rounded-full mx-auto"></div>
                    <p className="text-sm text-gray-500 mt-2">Loading datasets...</p>
                  </div>
                ) : treeData?.tree ? (
                  <ParentSelector
                    treeNodes={treeData.tree}
                    selectedId={parentId}
                    onSelect={handleTreeSelect}
                    searchQuery={treeSearch}
                  />
                ) : (
                  <div className="border border-gray-200 rounded-lg p-4 text-gray-500 text-sm text-center">
                    No datasets available
                  </div>
                )}
              </div>
            )}

            {/* Error message */}
            {error && (
              <div className="flex items-center gap-2 bg-red-50 border border-red-200 rounded-lg p-3 text-red-700 text-sm">
                <svg className="w-4 h-4 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                {error}
              </div>
            )}

            {/* Submit buttons */}
            <div className="flex gap-3 pt-2">
              <button
                type="submit"
                disabled={isSubmitting}
                className="flex-1 px-4 py-2.5 bg-brand-600 text-white text-sm font-medium rounded-lg hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                {isSubmitting ? (
                  <span className="flex items-center justify-center gap-2">
                    <div className="animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full"></div>
                    Importing...
                  </span>
                ) : (
                  'Import Dataset'
                )}
              </button>
              <button
                type="button"
                onClick={() => history.back()}
                className="px-4 py-2.5 border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 transition-colors"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
