'use client';

import { useEffect, useMemo, useState } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import { projectApi } from '@/lib/api';

export default function ProjectDatasetsPage() {
  const params = useParams<{ projectNumber: string }>();
  const projectNumber = Number(params.projectNumber);
  const searchParams = useSearchParams();
  const router = useRouter();

  // View mode state (table | tree)
  const viewMode = useMemo(() => searchParams.get('view') || 'table', [searchParams]);
  const [treeSearchQuery, setTreeSearchQuery] = useState('');

  // URL-driven parameters
  const page = useMemo(() => Number(searchParams.get('page') || 1), [searchParams]);
  const per = useMemo(() => Number(searchParams.get('per') || 50), [searchParams]);
  const qParam = useMemo(() => searchParams.get('q') || '', [searchParams]);

  // Local input state for search box with debouncing
  const [qLocal, setQLocal] = useState(qParam);
  useEffect(() => { setQLocal(qParam); }, [qParam]);

  // Debounced search - update URL after 300ms of no typing
  useEffect(() => {
    const timeoutId = setTimeout(() => {
      const sp = new URLSearchParams(searchParams);
      if (qLocal) sp.set('q', qLocal); else sp.delete('q');
      sp.set('page', '1'); // Reset to page 1 on new search
      
      // Only update URL if the search term actually changed
      if (qLocal !== qParam) {
        router.push(`?${sp.toString()}`);
      }
    }, 300);

    return () => clearTimeout(timeoutId);
  }, [qLocal, qParam, searchParams, router]);

  const { data, isLoading, error } = useQuery({
    queryKey: ['datasets', projectNumber, { q: qParam, page, per }],
    queryFn: () => projectApi.getProjectDatasets(projectNumber, { q: qParam, page, per }),
    keepPreviousData: true,
    staleTime: 60_000,
  });

  // Tree data query (enabled only when tree view)
  const { data: treeData, isLoading: isTreeLoading, error: treeError } = useQuery({
    queryKey: ['datasets-tree', projectNumber],
    queryFn: () => apiClient.getProjectDatasetsTree(projectNumber),
    enabled: viewMode === 'tree',
    staleTime: 60_000,
  });

  const selectedSet = useMemo(() => {
    const sel = searchParams.get('selected');
    return new Set((sel ? sel.split(',') : []).map((s) => Number(s)));
  }, [searchParams]);

  const updateSelectedInUrl = (ids: Set<number>) => {
    const sp = new URLSearchParams(searchParams);
    if (ids.size > 0) sp.set('selected', Array.from(ids).join(',')); else sp.delete('selected');
    router.push(`?${sp.toString()}`);
  };

  const toggleSelect = (id: number) => {
    const ids = new Set(selectedSet);
    if (ids.has(id)) ids.delete(id); else ids.add(id);
    updateSelectedInUrl(ids);
  };

  const onSearch = (e: React.FormEvent) => {
    e.preventDefault();
    // Search is now handled by debounce, but keep form for accessibility
  };

  const onChangePer = (nextPer: number) => {
    const sp = new URLSearchParams(searchParams);
    sp.set('per', String(nextPer));
    sp.set('page', '1');
    router.push(`?${sp.toString()}`);
  };

  const goToPage = (nextPage: number) => {
    const sp = new URLSearchParams(searchParams);
    sp.set('page', String(nextPage));
    router.push(`?${sp.toString()}`);
  };

  if (isLoading) return (
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
  
  if (error) return (
    <div className="container mx-auto px-6 py-8">
      <div className="text-center py-12">
        <div className="text-red-600 text-lg font-medium mb-2">Failed to load datasets</div>
        <p className="text-gray-500 mb-4">There was an error loading the datasets for this project.</p>
      </div>
    </div>
  );

  const datasets = data?.datasets ?? [];
  const total = data?.total_count ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / per));
  const allIds = datasets.map((d) => d.id);
  const allSelectedOnPage = allIds.length > 0 && allIds.every((id) => selectedSet.has(id));
  const startIndex = (page - 1) * per + Math.min(1, total);
  const endIndex = Math.min(page * per, total);

  return (
    <div className="container mx-auto px-6 py-8">
      {/* Breadcrumb navigation */}
      <nav className="mb-6" aria-label="Breadcrumb">
        <ol className="flex items-center space-x-2 text-sm text-gray-500">
          <li>
            <Link href="/projects" className="hover:text-gray-700">Projects</Link>
          </li>
          <li>/</li>
          <li>
            <Link href={`/projects/${projectNumber}`} className="hover:text-gray-700">Project {projectNumber}</Link>
          </li>
          <li>/</li>
          <li className="text-gray-900 font-medium" aria-current="page">Datasets</li>
        </ol>
      </nav>

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Project {projectNumber} - Datasets</h1>
        <Link 
          href={`/projects/${projectNumber}`} 
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          ← Back to Project
        </Link>
      </div>

      <form onSubmit={onSearch} className="mb-4 flex items-center gap-4">
        <div className="flex items-center gap-2">
          <label className="text-sm text-gray-600">Show</label>
          <select
            value={per}
            onChange={(e) => onChangePer(Number(e.target.value))}
            className="border rounded px-2 py-1"
          >
            Table View
          </button>
          <button
            onClick={() => {
              const sp = new URLSearchParams(searchParams);
              sp.set('view', 'tree');
              router.push(`?${sp.toString()}`);
            }}
            className={`px-3 py-1 rounded ${viewMode === 'tree' ? 'bg-blue-600 text-white' : 'bg-gray-200'}`}
          >
            Tree View
          </button>
        </span>
      </h1>

      {viewMode === 'tree' ? (
        <div>
          <div className="mb-4 flex items-center gap-4">
            <input
              value={treeSearchQuery}
              onChange={(e) => setTreeSearchQuery(e.target.value)}
              placeholder="Search in tree..."
              className="border rounded px-3 py-2 flex-1"
            />
          </div>

          {isTreeLoading && <div className="p-6">Loading tree...</div>}
          {treeError && <div className="p-6 text-red-600">Failed to load tree</div>}
          {treeData && (
            <DatasetTree
              treeNodes={treeData.tree}
              selectedIds={selectedSet}
              onSelectionChange={updateSelectedInUrl}
              projectNumber={projectNumber}
              searchQuery={treeSearchQuery}
            />
          )}
        </div>
      ) : (
        <>
          <form onSubmit={onSearch} className="mb-4 flex items-center gap-4">
            <div className="flex items-center gap-2">
              <label className="text-sm text-gray-600">Show</label>
              <select
                value={per}
                onChange={(e) => onChangePer(Number(e.target.value))}
                className="border rounded px-2 py-1"
              >
                <option value={10}>10</option>
                <option value={25}>25</option>
                <option value={50}>50</option>
                <option value={100}>100</option>
              </select>
              <span className="text-sm text-gray-600">entries</span>
            </div>

            <div className="flex items-center gap-2">
              <input value={qLocal} onChange={(e) => setQLocal(e.target.value)} placeholder="Search name..." className="border rounded px-3 py-2" />
              <button type="submit" className="px-4 py-2 bg-blue-600 text-white rounded">Search</button>
            </div>
          </form>

          {isLoading && <div className="p-6">Loading datasets...</div>}
          {error && <div className="p-6 text-red-600">Failed to load datasets</div>}

          <div className="overflow-x-auto">
            <table className="min-w-full border">
              <thead className="bg-gray-50">
                <tr>
                  <th className="p-2 border text-center">
                    <input
                      type="checkbox"
                      checked={allSelectedOnPage}
                      onChange={() => {
                        const next = new Set(selectedSet);
                        if (allSelectedOnPage) {
                          allIds.forEach((id) => next.delete(id));
                        } else {
                          allIds.forEach((id) => next.add(id));
                        }
                        updateSelectedInUrl(next);
                      }}
                    />
                  </th>
                  <th className="p-2 border">ID</th>
                  <th className="p-2 border">Name</th>
                  <th className="p-2 border">SushiApp</th>
                  <th className="p-2 border">Samples</th>
                  <th className="p-2 border">ParentID</th>
                  <th className="p-2 border">Children</th>
                  <th className="p-2 border">Who</th>
                  <th className="p-2 border">Created</th>
                  <th className="p-2 border">BFabricID</th>
                </tr>
              </thead>
              <tbody>
                {datasets.map((ds) => (
                  <tr key={ds.id} className="odd:bg-white even:bg-gray-50">
                    <td className="p-2 border text-center">
                      <input type="checkbox" checked={selectedSet.has(ds.id)} onChange={() => toggleSelect(ds.id)} />
                    </td>
                    <td className="p-2 border">{ds.id}</td>
                    <td className="p-2 border">
                      <a href={`/projects/${projectNumber}/datasets/${ds.id}`} className="text-blue-600 hover:underline">{ds.name}</a>
                    </td>
                    <td className="p-2 border">{ds.sushi_app_name || ''}</td>
                    <td className="p-2 border">{ds.completed_samples ?? 0} / {ds.samples_length ?? 0}</td>
                    <td className="p-2 border">
                      {ds.parent_id ? (
                        <a href={`/projects/${projectNumber}/datasets/${ds.parent_id}`} className="text-blue-600 hover:underline">{ds.parent_id}</a>
                      ) : ''}
                    </td>
                    <td className="p-2 border">
                      {(ds.children_ids || []).map((cid, idx) => (
                        <span key={cid}>
                          <a href={`/projects/${projectNumber}/datasets/${cid}`} className="text-blue-600 hover:underline">{cid}</a>
                          {idx < (ds.children_ids || []).length - 1 ? ', ' : ''}
                        </span>
                      ))}
                    </td>
                    <td className="p-2 border">{ds.user_login || ''}</td>
                    <td className="p-2 border">{new Date(ds.created_at).toLocaleString()}</td>
                    <td className="p-2 border">
                      {ds.bfabric_id ? (
                        <a
                          href={`https://fgcz-bfabric.uzh.ch/bfabric/dataset/show.html?id=${ds.bfabric_id}&tab=details`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-blue-600 hover:underline"
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

          <div className="mt-4 flex items-center justify-between gap-2">
            <div className="text-sm text-gray-600">Showing {startIndex} to {endIndex} of {total} entries</div>
            <div className="flex items-center gap-2">
              <button disabled={page <= 1} onClick={() => goToPage(page - 1)} className="px-3 py-1 border rounded disabled:opacity-50">Prev</button>
              <span>Page {page} / {totalPages}</span>
              <button disabled={page >= totalPages} onClick={() => goToPage(page + 1)} className="px-3 py-1 border rounded disabled:opacity-50">Next</button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}



