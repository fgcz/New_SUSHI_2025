'use client';

import { useState } from 'react';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { projectApi } from '@/lib/api';
import { usePagination } from '@/lib/hooks';

export default function GlobalDatasetListPage() {
  // Pagination via shared hook
  const { page, per, goToPage, changePerPage } = usePagination(10);

  // Filter state
  const [selectedApp, setSelectedApp] = useState<string>('');
  const [selectedRetiredApp, setSelectedRetiredApp] = useState<string>('');

  // Fetch applications list
  const { data: appsData } = useQuery({
    queryKey: ['applications-list'],
    queryFn: () => projectApi.getApplicationsList(),
    staleTime: 300_000,
  });


  const { data, isLoading, error } = useQuery({
    queryKey: ['datasets-global', { app: selectedApp, retiredApp: selectedRetiredApp, page, per }],
    queryFn: () => projectApi.getGlobalDatasets({ q: selectedApp || selectedRetiredApp, page, per }),
    placeholderData: keepPreviousData,
    staleTime: 60_000,
  });

  if (isLoading) return <DatasetsPageSkeleton />;

  if (error) return (
    <div className="container mx-auto px-6 py-8">
      <div className="text-center py-12">
        <div className="text-red-600 text-lg font-medium mb-2">Failed to load datasets</div>
        <p className="text-gray-500 mb-4">There was an error loading the datasets.</p>
      </div>
    </div>
  );

  const datasets = data?.datasets ?? [];
  const total = data?.total_count ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / per));
  const startIndex = (page - 1) * per + Math.min(1, total);
  const endIndex = Math.min(page * per, total);

  return (
    <div className="container mx-auto px-6 py-8">
      <h1 className="text-2xl font-bold mb-4">Find DataSets</h1>

      {/* Filters */}
      <div className="flex flex-col gap-1 mb-4">
        <div className="flex items-center gap-1 text-sm">
          <span className="text-gray-700 font-medium">SUSHIApp:</span>
          <select
            value={selectedApp}
            onChange={(e) => { setSelectedApp(e.target.value); setSelectedRetiredApp(''); }}
            className="w-40 border border-gray-300 rounded-md px-2 py-1 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          >
            <option value="">--- select ---</option>
            {appsData?.sushiApps.map((app) => (
              <option key={app} value={app}>{app}</option>
            ))}
          </select>
        </div>
        <div className="flex items-center gap-1 text-sm">
          <span className="text-gray-700 font-medium">RetiredApp:</span>
          <select
            value={selectedRetiredApp}
            onChange={(e) => { setSelectedRetiredApp(e.target.value); setSelectedApp(''); }}
            className="w-40 border border-gray-300 rounded-md px-2 py-1 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          >
            <option value="">--- select ---</option>
            {appsData?.retiredApps.map((app) => (
              <option key={app} value={app}>{app}</option>
            ))}
          </select>
        </div>
      </div>

      {/* Toolbar */}
      <div className="flex items-center gap-3 mb-4">
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
      </div>

      <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
        <div className="overflow-x-auto">
        <table className="min-w-full">
          <thead className="bg-brand-300 text-gray-800">
            <tr>
              <th className="px-3 py-2 text-left font-semibold">ID</th>
              <th className="px-3 py-2 text-left font-semibold">Name</th>
              <th className="px-3 py-2 text-left font-semibold">Project</th>
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
                <td className="px-3 py-2 text-gray-600">{ds.id}</td>
                <td className="px-3 py-2">
                  <a href={`/projects/${ds.project_number}/datasets/${ds.id}`} className="text-brand-700 hover:text-brand-900 hover:underline font-medium">{ds.name}</a>
                </td>
                <td className="px-3 py-2">
                  <a href={`/projects/${ds.project_number}`} className="text-brand-600 hover:text-brand-800 hover:underline">{ds.project_number}</a>
                </td>
                <td className="px-3 py-2">{ds.sushi_app_name || ''}</td>
                <td className="px-3 py-2 text-gray-600">{ds.completed_samples ?? 0} / {ds.samples_count ?? 0}</td>
                <td className="px-3 py-2">
                  {ds.parent_id ? (
                    <a href={`/projects/${ds.project_number}/datasets/${ds.parent_id}`} className="text-brand-600 hover:text-brand-800 hover:underline">{ds.parent_id}</a>
                  ) : <span className="text-gray-300">—</span>}
                </td>
                <td className="px-3 py-2">
                  {(ds.children_ids || []).length > 0 ? (ds.children_ids || []).map((cid, idx) => (
                    <span key={cid}>
                      <a href={`/projects/${ds.project_number}/datasets/${cid}`} className="text-brand-600 hover:text-brand-800 hover:underline">{cid}</a>
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
