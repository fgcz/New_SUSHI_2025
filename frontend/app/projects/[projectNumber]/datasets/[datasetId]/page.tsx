'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';
import { useDatasetBase, useDatasetTree } from '@/lib/hooks';
import { datasetApi } from '@/lib/api';
import DatasetTreeRcTree from '../DatasetTreeRcTree';
import DatasetApps from './DatasetApps';
import DatasetSamples from './DatasetSamples';
import DatasetInfoCard from './DatasetInfoCard';

export default function DatasetDetailPage() {
  const params = useParams<{ projectNumber: string; datasetId: string }>();
  const router = useRouter();
  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);

  const { dataset, isLoading: isDatasetLoading, error: datasetError, notFound: datasetNotFound } = useDatasetBase(datasetId);
  const { datasetTree, isLoading: isTreeLoading, error: treeError } = useDatasetTree(datasetId);

  // State for expandable input actions
  const [activeAction, setActiveAction] = useState<'comment' | 'rename' | 'bfabricId' | null>(null);
  const [inputValue, setInputValue] = useState('');

  const handleActionSubmit = async () => {
    if (!inputValue.trim()) return;
    if (activeAction === 'comment') {
      await datasetApi.addComment(datasetId, inputValue);
    } else if (activeAction === 'rename') {
      await datasetApi.renameDataset(datasetId, inputValue);
    } else if (activeAction === 'bfabricId') {
      await datasetApi.setBFabricId(datasetId, inputValue);
    }
    // TODO: Replace alert with toast notification and data refresh
    alert(`${activeAction === 'comment' ? 'Comment added' : activeAction === 'rename' ? 'Dataset renamed' : 'B-Fabric ID set'} successfully`);
    setActiveAction(null);
    setInputValue('');
  };

  const handleActionCancel = () => {
    setActiveAction(null);
    setInputValue('');
  };

  if (isDatasetLoading) return (
    <div className="container mx-auto px-6 py-8">
      <div className="animate-pulse">
        {/* Breadcrumb skeleton */}
        <div className="h-4 bg-gray-200 rounded w-48 mb-6"></div>
        
        {/* Title skeleton */}
        <div className="h-8 bg-gray-200 rounded w-64 mb-6"></div>
        
        {/* Card skeleton */}
        <div className="bg-white border rounded-lg overflow-hidden">
          <div className="p-6 space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-3">
                <div className="h-6 bg-gray-200 rounded w-32 mb-4"></div>
                {[...Array(5)].map((_, i) => (
                  <div key={i} className="flex justify-between">
                    <div className="h-4 bg-gray-200 rounded w-20"></div>
                    <div className="h-4 bg-gray-200 rounded w-24"></div>
                  </div>
                ))}
              </div>
              <div className="space-y-3">
                <div className="h-6 bg-gray-200 rounded w-40 mb-4"></div>
                {[...Array(3)].map((_, i) => (
                  <div key={i} className="flex justify-between">
                    <div className="h-4 bg-gray-200 rounded w-24"></div>
                    <div className="h-4 bg-gray-200 rounded w-16"></div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
  
  if (datasetError) return (
    <div className="container mx-auto px-6 py-8">
      <div className="text-center py-12">
        <div className="text-red-600 text-lg font-medium mb-2">Failed to load dataset</div>
        <p className="text-gray-500 mb-4">There was an error loading the dataset information.</p>
        <Link href={`/projects/${projectNumber}/datasets`} className="text-brand-600 hover:underline">
          ← Back to Datasets
        </Link>
      </div>
    </div>
  );

  if (datasetNotFound || !dataset) {
    return (
      <div className="container mx-auto px-6 py-8">
        <h1 className="text-2xl font-bold mb-4 text-red-600">Dataset Not Found</h1>
        <p className="text-gray-700 mb-6">Dataset {datasetId} was not found in project {projectNumber}.</p>
        <Link href={`/projects/${projectNumber}/datasets`} className="text-brand-600 hover:underline">← Back to Datasets</Link>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-6 py-8">

      <div className="flex items-center justify-between mb-2">
        <Breadcrumbs items={[
          { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
          { label: 'Datasets', href: `/projects/${projectNumber}/datasets` },
          { label: dataset.name, active: true }
        ]} />

        {/* Quick Actions - top right */}
        <div className="flex items-center gap-1">
          {/* Data Folder button - handles single or multiple paths */}
          {dataset.data_paths.length === 1 ? (
            <button
              onClick={() => router.push(`/files/${dataset.data_paths[0]}`)}
              className="px-2.5 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors"
              title="Data Folder"
            >
              Data Folder
            </button>
          ) : dataset.data_paths.length > 1 ? (
            <div className="relative group">
              <button
                className="px-2.5 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors"
                title="Data Folders"
              >
                Data Folders ({dataset.data_paths.length})
              </button>
              <div className="absolute top-full left-0 mt-1 bg-white border border-gray-200 rounded-md shadow-lg z-50 min-w-48 hidden group-hover:block">
                {dataset.data_paths.map((path) => (
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
          <button
            onClick={() => router.push(`/projects/${projectNumber}/datasets/${datasetId}/samples/edit`)}
            className="px-2.5 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors"
            title="Edit Samples"
          >
            Edit Samples
          </button>
          <button
            onClick={() => router.push(`/projects/${projectNumber}/datasets/${datasetId}/jobs`)}
            className="px-2.5 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 transition-colors"
            title="Job Scripts"
          >
            Jobs
          </button>
        </div>
      </div>

      {/* Dataset Actions */}
      <div className="flex flex-wrap gap-1 mb-3">
        <button
          className={`px-2 py-1 text-xs font-medium rounded ${activeAction === 'comment' ? 'bg-brand-600 text-white border border-brand-600' : 'text-gray-700 bg-white border border-gray-300 hover:bg-gray-50'}`}
          onClick={() => { setActiveAction(activeAction === 'comment' ? null : 'comment'); setInputValue(''); }}
        >
          Comment
        </button>
        <button
          className={`px-2 py-1 text-xs font-medium rounded ${activeAction === 'rename' ? 'bg-brand-600 text-white border border-brand-600' : 'text-gray-700 bg-white border border-gray-300 hover:bg-gray-50'}`}
          onClick={() => { setActiveAction(activeAction === 'rename' ? null : 'rename'); setInputValue(activeAction === 'rename' ? '' : dataset.name); }}
        >
          Rename
        </button>
        <button
          className="px-2 py-1 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50"
          onClick={async () => {
            const { downloadUrl } = await datasetApi.downloadDataset(datasetId);
            // TODO: Trigger actual download when backend returns real URL
            alert(`Download URL: ${downloadUrl}`);
          }}
        >
          Download
        </button>
        <button
          className="px-2 py-1 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50"
          onClick={() => router.push(`/projects/${projectNumber}/datasets/${datasetId}/jobs`)}
        >
          Job Scripts
        </button>
        <button
          className="px-2 py-1 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50"
          onClick={async () => {
            const targetId = prompt('Enter target dataset ID to merge with:');
            if (targetId && !isNaN(Number(targetId))) {
              await datasetApi.mergeDataset(datasetId, Number(targetId));
              alert('Merge request submitted');
            }
          }}
        >
          Merge with another dataset
        </button>
        <button
          className="px-2 py-1 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50"
          onClick={() => router.push(`/projects/${projectNumber}/datasets/${datasetId}/parameters`)}
        >
          Parameters
        </button>
        <button
          className="px-2 py-1 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50"
          onClick={async () => {
            const { appName } = await datasetApi.getResubmitData(datasetId);
            router.push(`/projects/${projectNumber}/datasets/${datasetId}/run-application/${appName}?resubmit=true`);
          }}
        >
          Run Again
        </button>
        <button
          className={`px-2 py-1 text-xs font-medium rounded ${activeAction === 'bfabricId' ? 'bg-brand-600 text-white border border-brand-600' : 'text-gray-700 bg-white border border-gray-300 hover:bg-gray-50'}`}
          onClick={() => { setActiveAction(activeAction === 'bfabricId' ? null : 'bfabricId'); setInputValue(''); }}
        >
          B-Fabric ID
        </button>
        <button
          className="px-2 py-1 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50"
          onClick={() => window.open(`https://geo-uploader.fgcz.uzh.ch/sessions/new/datasets/${datasetId}`, '_blank')}
        >
          GEO-uploader
        </button>
        <button
          className="px-2 py-1 text-xs font-medium text-red-600 bg-white border border-red-300 rounded hover:bg-red-50"
          onClick={async () => {
            if (confirm(`Are you sure you want to delete dataset "${dataset.name}"?`)) {
              await datasetApi.deleteDataset(datasetId);
              router.push(`/projects/${projectNumber}/datasets`);
            }
          }}
        >
          Delete
        </button>
      </div>

      {/* Expandable input field for Comment/Rename/B-Fabric ID */}
      {activeAction && (
        <div className="mb-3">
          <div className="flex items-center gap-2">
            <label className="text-sm font-medium text-gray-700 min-w-24">
              {activeAction === 'comment' ? 'Comment:' : activeAction === 'rename' ? 'New name:' : 'B-Fabric ID:'}
            </label>
            <input
              type="text"
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              placeholder={activeAction === 'comment' ? 'Enter comment...' : activeAction === 'rename' ? 'Enter new name...' : 'Enter B-Fabric ID...'}
              className="flex-1 px-3 py-1.5 text-sm border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleActionSubmit();
                if (e.key === 'Escape') handleActionCancel();
              }}
            />
            <button
              onClick={handleActionSubmit}
              disabled={!inputValue.trim()}
              className="px-3 py-1.5 text-xs font-medium text-white bg-brand-600 rounded hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Submit
            </button>
            <button
              onClick={handleActionCancel}
              className="px-3 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Main layout with tree on left and info on right */}
      <div className="grid grid-cols-1 lg:grid-cols-10 gap-6">
        {/* Left side - Tree (70%) */}
        <div className="lg:col-span-7">
          {isTreeLoading && <div className="h-64 border rounded-lg bg-gray-50 flex items-center justify-center"><div className="text-gray-500">Loading tree...</div></div>}
          {treeError && <div className="h-64 border rounded-lg bg-red-50 flex items-center justify-center"><div className="text-red-600">Failed to load tree data</div></div>}
          {datasetTree && (
            <DatasetTreeRcTree
              treeNodes={datasetTree.tree}
              projectNumber={projectNumber}
              currentDatasetId={datasetId}
              variant="geist"
              noFade
            />
          )}
        </div>
        
        {/* Right side - Dataset Information (30%) */}
        <div className="lg:col-span-3" style={{ height: '400px' }}>
          <DatasetInfoCard dataset={dataset} />
        </div>
      </div>
      
      <div className="bg-white border rounded-lg overflow-hidden mt-6">
        <div className="p-6">
          <DatasetSamples samples={dataset.samples} datasetId={datasetId} projectNumber={projectNumber} dataPaths={dataset.data_paths} />

          <div className="mt-6 pt-4 border-t">
            <h3 className="text-lg font-semibold mb-4">Runnable Applications</h3>
            <DatasetApps runnableApps={dataset.applications} datasetId={datasetId} projectNumber={projectNumber} />
          </div>
        </div>
      </div>
    </div>
  );
}


