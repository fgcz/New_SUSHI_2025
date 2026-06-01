'use client';

import { useMemo, useState } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { projectApi } from '@/lib/api';
import { usePagination, useSearch } from '@/lib/hooks';
import DatasetTreeRcTree from './DatasetTreeRcTree';

export default function ProjectDatasetsPage() {
  const params = useParams<{ projectNumber: string }>();
  const projectNumber = Number(params.projectNumber);
  const searchParams = useSearchParams();
  const router = useRouter();

  // View mode (table | tree)
  const viewMode = useMemo(() => searchParams.get('view') || 'table', [searchParams]);
  const [treeSearchQuery, setTreeSearchQuery] = useState('');

  // Pagination and search via shared hooks
  const { page, per, goToPage, changePerPage } = usePagination(10);
  const { searchQuery, localQuery, setLocalQuery, onSubmit } = useSearch('q');

  // Local selection state (no need for URL sync)
  const [selectedSet, setSelectedSet] = useState<Set<number>>(new Set());
  const [selectMode, setSelectMode] = useState(false);

  const exitSelectMode = () => { setSelectMode(false); setSelectedSet(new Set()); };

  const toggleSelect = (id: number) => {
    setSelectedSet(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const { data, isLoading, error } = useQuery({
    queryKey: ['datasets', projectNumber, { datasetName: searchQuery, page, per }],
    queryFn: () => projectApi.getProjectDatasets(projectNumber, { datasetName: searchQuery, page, per }),
    placeholderData: keepPreviousData,
    staleTime: 60_000,
  });

  const isTreeView = viewMode === 'tree' || viewMode === 'tree3';

  // Tree data query (shared across all three tree views)
  const { data: treeData, isLoading: isTreeLoading, error: treeError } = useQuery({
    queryKey: ['datasets-tree', projectNumber],
    queryFn: () => projectApi.getProjectDatasetsTree(projectNumber),
    enabled: isTreeView,
    staleTime: 60_000,
  });

  const downloadAllDatasets = async () => {
    await projectApi.getDownloadAllDatasets(projectNumber);
    alert(`Called mock getDownloadAllDataset`);
  }

  const deleteDatasets = async (datasets: number[]) => {
    alert(`Called mock deleteDatasets(${datasets})`)
  }

  if (isLoading) return <DatasetsPageSkeleton />;
  
  if (error) return (
    <div className="container mx-auto px-6 py-8">
      <div className="text-center py-12">
        <div className="text-red-600 text-lg font-medium mb-2">Failed to load datasets</div>
        <p className="text-gray-500 mb-4">There was an error loading the datasets for this project.</p>
      </div>
    </div>
  );

  const datasets = data?.datasets ?? [];
  const total = data?.pagination.total_count ?? 0;
  const totalPages = data?.pagination.total_pages ?? 0;
  const allIds = datasets.map((d) => d.id);
  const allSelectedOnPage = allIds.length > 0 && allIds.every((id) => selectedSet.has(id));
  const startIndex = (page - 1) * per + Math.min(1, total);
  const endIndex = Math.min(page * per, total);

  return (
    <div className="container mx-auto px-6 py-8">
      <h1 className="text-2xl font-bold mb-4">Project {projectNumber} - DataSets</h1>

      {/* Unified toolbar */}
      <div className="flex items-center gap-3 mb-4">
        {/* View toggle group */}
        <div className="inline-flex rounded-md bg-gray-100 p-0.5">
          {(['table', 'tree', 'tree3'] as const).map((mode) => (
            <button
              key={mode}
              onClick={() => {
                const sp = new URLSearchParams(searchParams.toString());
                if (mode === 'table') sp.delete('view'); else sp.set('view', mode);
                router.push(`?${sp.toString()}`);
                exitSelectMode();
              }}
              className={`px-3 py-1.5 text-sm font-medium rounded transition-all ${
                viewMode === mode
                  ? 'bg-white text-gray-900 shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              {mode === 'table' ? 'Table' : mode === 'tree' ? 'Tree' : 'Tree 3'}
            </button>
          ))}
        </div>

        <div className="w-px h-6 bg-gray-300" />

        {/* Search input - different for table vs tree */}
        {isTreeView ? (
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-2.5 flex items-center pointer-events-none">
              <svg className="h-4 w-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </div>
            <input
              value={treeSearchQuery}
              onChange={(e) => setTreeSearchQuery(e.target.value)}
              placeholder="Search tree..."
              className="w-48 pl-8 pr-3 py-1.5 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 bg-white"
            />
          </div>
        ) : (
          <>
            <input
              value={localQuery}
              onChange={(e) => setLocalQuery(e.target.value)}
              placeholder="Search name..."
              className="w-48 border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
            />
            <div className="flex items-center gap-1.5 text-sm text-gray-600">
              <span>Show</span>
              <select
                value={per}
                onChange={(e) => changePerPage(Number(e.target.value))}
                className="border border-gray-300 rounded-md px-2 py-1.5 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
              >
                <option value={10}>10</option>
                <option value={25}>25</option>
                <option value={50}>50</option>
                <option value={100}>100</option>
              </select>
            </div>
          </>
        )}

        {/* Spacer */}
        <div className="flex-1" />

        {/* Action buttons - right aligned */}
        {isTreeView ? (
          selectMode ? (
            <>
              <button
                className="px-3 py-1.5 bg-white text-red-600 border border-red-300 rounded-md text-sm font-medium hover:bg-red-50 hover:border-red-400 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-white disabled:hover:border-red-300 transition-colors"
                disabled={selectedSet.size === 0}
                onClick={async () => { await deleteDatasets(Array.from(selectedSet)); exitSelectMode(); }}
              >
                Delete ({selectedSet.size})
              </button>
              <button
                className="px-3 py-1.5 bg-white text-gray-600 border border-gray-300 rounded-md text-sm font-medium hover:bg-gray-50 transition-colors"
                onClick={exitSelectMode}
              >
                Cancel
              </button>
            </>
          ) : (
            <button
              className="px-3 py-1.5 bg-white text-gray-700 border border-gray-300 rounded-md text-sm font-medium hover:bg-gray-50 transition-colors"
              onClick={() => setSelectMode(true)}
            >
              Select
            </button>
          )
        ) : (
          <button
            className="px-3 py-1.5 bg-white text-red-600 border border-red-300 rounded-md text-sm font-medium hover:bg-red-50 hover:border-red-400 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-white disabled:hover:border-red-300 transition-colors"
            disabled={selectedSet.size === 0}
            onClick={() => deleteDatasets(Array.from(selectedSet))}
          >
            Delete ({selectedSet.size})
          </button>
        )}
        <button
          className="px-3 py-1.5 bg-brand-600 text-white rounded-md text-sm font-medium hover:bg-brand-700 transition-colors"
          onClick={() => downloadAllDatasets()}
        >
          Download All
        </button>
      </div>

      {isTreeView ? (
        <div>
          {isTreeLoading && <div className="p-6 text-gray-500">Loading tree...</div>}
          {treeError && <div className="p-6 text-red-600">Failed to load tree</div>}
          {treeData && (
            <DatasetTreeRcTree
              treeNodes={treeData.tree}
              selectedIds={selectMode ? selectedSet : undefined}
              onSelectionChange={selectMode ? setSelectedSet : undefined}
              projectNumber={projectNumber}
              searchQuery={treeSearchQuery}
              variant={viewMode === 'tree3' ? 'geist' : 'rctree'}
            />
          )}
        </div>
      ) : (
        <>
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
            <div className="overflow-x-auto">
            <table className="min-w-full">
              <thead className="bg-brand-300 text-gray-800">
                <tr>
                  <th className="px-3 py-2 text-center w-10 font-semibold">
                    <input
                      type="checkbox"
                      className="rounded border-gray-400"
                      checked={allSelectedOnPage}
                      onChange={() => {
                        setSelectedSet(prev => {
                          const next = new Set(prev);
                          if (allSelectedOnPage) {
                            allIds.forEach((id) => next.delete(id));
                          } else {
                            allIds.forEach((id) => next.add(id));
                          }
                          return next;
                        });
                      }}
                    />
                  </th>
                  <th className="px-3 py-2 text-left font-semibold">ID</th>
                  <th className="px-3 py-2 text-left font-semibold">Name</th>
                  <th className="px-3 py-2 text-left font-semibold">SushiApp</th>
                  <th className="px-3 py-2 text-left font-semibold">Samples</th>
                  <th className="px-3 py-2 text-left font-semibold">ParentID</th>
                  <th className="px-3 py-2 text-left font-semibold">Children</th>
                  <th className="px-3 py-2 text-left font-semibold">Who</th>
                  <th className="px-3 py-2 text-left font-semibold">Created</th>
                  <th className="px-3 py-2 text-left font-semibold">BFabricID</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 text-sm">
                {datasets.map((ds) => (
                  <tr key={ds.id} className="odd:bg-white even:bg-gray-50/50 hover:bg-brand-50 transition-colors">
                    <td className="px-3 py-2 text-center">
                      <input type="checkbox" className="rounded border-gray-300" checked={selectedSet.has(ds.id)} onChange={() => toggleSelect(ds.id)} />
                    </td>
                    <td className="px-3 py-2 text-gray-600">{ds.id}</td>
                    {/* <td className="px-3 py-2 max-w-[200px] truncate" title={ds.name}> */}
                    <td className="px-3 py-2">
                      <a href={`/projects/${projectNumber}/datasets/${ds.id}`} className="text-brand-700 hover:text-brand-900 hover:underline font-medium">{ds.name}</a>
                    </td>
                    {/* <td className="px-3 py-2 text-gray-600 max-w-[150px] truncate" title={ds.sushi_app_name || ''}>{ds.sushi_app_name || ''}</td> */}
                    <td className="px-3 py-2">{ds.sushi_app_name || ''}</td>
                    <td className="px-3 py-2 text-gray-600">{ds.completed_samples ?? 0} / {ds.samples_count ?? 0}</td>
                    <td className="px-3 py-2">
                      {ds.parent_id ? (
                        <a href={`/projects/${projectNumber}/datasets/${ds.parent_id}`} className="text-brand-600 hover:text-brand-800 hover:underline">{ds.parent_id}</a>
                      ) : <span className="text-gray-300">—</span>}
                    </td>
                    <td className="px-3 py-2">
                      {(ds.children_ids || []).length > 0 ? (ds.children_ids || []).map((cid, idx) => (
                        <span key={cid}>
                          <a href={`/projects/${projectNumber}/datasets/${cid}`} className="text-brand-600 hover:text-brand-800 hover:underline">{cid}</a>
                          {idx < (ds.children_ids || []).length - 1 ? ', ' : ''}
                        </span>
                      )) : <span className="text-gray-300">—</span>}
                    </td>
                    <td className="px-3 py-2 text-gray-600">{ds.user_login || ''}</td>
                    <td className="px-3 py-2 text-gray-500 max-w-[120px] truncate" title={new Date(ds.created_at).toLocaleString()}>{new Date(ds.created_at).toLocaleString()}</td>
                    <td className="px-3 py-2">
                      {ds.bfabric_id ? (
                        <a
                          href={`https://fgcz-bfabric.uzh.ch/bfabric/dataset/show.html?id=${ds.bfabric_id}&tab=details`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-brand-600 hover:text-brand-800 hover:underline"
                        >
                          {ds.bfabric_id}
                        </a>
                      ) : ''}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            </div>
          </div>

          <div className="mt-4 flex items-center justify-between gap-2">
            <div className="text-sm text-gray-500">Showing {startIndex} to {endIndex} of {total} entries</div>
            <div className="flex items-center gap-1">
              <button disabled={page <= 1} onClick={() => goToPage(page - 1)} className="px-3 py-1.5 bg-white border border-gray-300 rounded-md text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-white transition-colors">Prev</button>
              <span className="text-sm text-gray-600 px-3">Page {page} / {totalPages}</span>
              <button disabled={page >= totalPages} onClick={() => goToPage(page + 1)} className="px-3 py-1.5 bg-white border border-gray-300 rounded-md text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-white transition-colors">Next</button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

function DatasetsPageSkeleton() {
  return (
    <div className="container mx-auto px-6 py-8">
      <div className="animate-pulse">
        {/* Title skeleton */}
        <div className="h-8 bg-gray-200 rounded w-64 mb-6"></div>

        {/* Search controls skeleton */}
        <div className="mb-4 flex items-center gap-4">
          <div className="flex items-center gap-2">
            <div className="h-4 bg-gray-200 rounded w-12"></div>
            <div className="h-8 bg-gray-200 rounded w-16"></div>
            <div className="h-4 bg-gray-200 rounded w-16"></div>
          </div>
          <div className="flex items-center gap-2">
            <div className="h-10 bg-gray-200 rounded w-48"></div>
            <div className="h-10 bg-gray-200 rounded w-20"></div>
          </div>
        </div>

        {/* Table skeleton */}
        <div className="overflow-x-auto">
          <div className="min-w-full border rounded-lg">
            {/* Table header skeleton */}
            <div className="bg-gray-100 border-b">
              <div className="flex">
                <div className="p-2 border-r flex-shrink-0 w-12">
                  <div className="h-4 bg-gray-300 rounded w-4 mx-auto"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-16">
                  <div className="h-4 bg-gray-300 rounded w-8"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-32">
                  <div className="h-4 bg-gray-300 rounded w-12"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-24">
                  <div className="h-4 bg-gray-300 rounded w-16"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-20">
                  <div className="h-4 bg-gray-300 rounded w-14"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-20">
                  <div className="h-4 bg-gray-300 rounded w-16"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-20">
                  <div className="h-4 bg-gray-300 rounded w-14"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-16">
                  <div className="h-4 bg-gray-300 rounded w-8"></div>
                </div>
                <div className="p-2 border-r flex-1 min-w-24">
                  <div className="h-4 bg-gray-300 rounded w-14"></div>
                </div>
                <div className="p-2 flex-1 min-w-24">
                  <div className="h-4 bg-gray-300 rounded w-18"></div>
                </div>
              </div>
            </div>

            {/* Table rows skeleton */}
            {[...Array(10)].map((_, i) => (
              <div key={i} className={`border-b ${i % 2 === 0 ? 'bg-white' : 'bg-gray-50'}`}>
                <div className="flex">
                  <div className="p-2 border-r flex-shrink-0 w-12">
                    <div className="h-4 bg-gray-200 rounded w-4 mx-auto"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-16">
                    <div className="h-4 bg-gray-200 rounded w-12"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-32">
                    <div className="h-4 bg-gray-200 rounded w-24"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-24">
                    <div className="h-4 bg-gray-200 rounded w-20"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-20">
                    <div className="h-4 bg-gray-200 rounded w-16"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-20">
                    <div className="h-4 bg-gray-200 rounded w-12"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-20">
                    <div className="h-4 bg-gray-200 rounded w-8"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-16">
                    <div className="h-4 bg-gray-200 rounded w-16"></div>
                  </div>
                  <div className="p-2 border-r flex-1 min-w-24">
                    <div className="h-4 bg-gray-200 rounded w-20"></div>
                  </div>
                  <div className="p-2 flex-1 min-w-24">
                    <div className="h-4 bg-gray-200 rounded w-16"></div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Pagination skeleton */}
        <div className="mt-4 flex items-center justify-between gap-2">
          <div className="h-4 bg-gray-200 rounded w-48"></div>
          <div className="flex items-center gap-2">
            <div className="h-8 bg-gray-200 rounded w-16"></div>
            <div className="h-4 bg-gray-200 rounded w-24"></div>
            <div className="h-8 bg-gray-200 rounded w-16"></div>
          </div>
        </div>
      </div>
    </div>
  );
}
