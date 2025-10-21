'use client';

import { useParams } from 'next/navigation';
import Link from 'next/link';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';
import { useProjectDatasets, useSearch, usePagination } from '@/lib/hooks';
import DatasetsPageSkeleton from './DatasetsPageSkeleton';

export default function ProjectDatasetsPage() {
  const params = useParams<{ projectNumber: string }>();
  const projectNumber = Number(params.projectNumber);

  const { searchQuery, localQuery, setLocalQuery, onSubmit } = useSearch();
  const { page, per, goToPage, changePerPage } = usePagination();

  const { 
    datasets, 
    total, 
    totalPages, 
    isLoading, 
    error, 
    isEmpty 
  } = useProjectDatasets({
    projectNumber,
    q: searchQuery,
    page,
    per
  });
  if (isLoading) return <DatasetsPageSkeleton />;
  
  if (error) return (
    <div className="container mx-auto px-6 py-8">
      <div className="text-center py-12">
        <div className="text-red-600 text-lg font-medium mb-2">Failed to load datasets</div>
        <p className="text-gray-500 mb-4">There was an error loading the datasets for this project.</p>
      </div>
    </div>
  );

  const startIndex = (page - 1) * per + Math.min(1, total);
  const endIndex = Math.min(page * per, total);

  return (
    <div className="container mx-auto px-6 py-8">

      <Breadcrumbs items={[
        { label: 'Projects', href: '/projects' },
        { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
        { label: 'Datasets', active: true }
      ]} />
      

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Project {projectNumber} - Datasets</h1>
        <Link 
          href={`/projects/${projectNumber}`} 
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          ← Back to Project
        </Link>
      </div>

      <form onSubmit={onSubmit} className="mb-4 flex items-center gap-4">
        <div className="flex items-center gap-2">
          <label className="text-sm text-gray-600">Show</label>
          <select
            value={per}
            onChange={(e) => changePerPage(Number(e.target.value))}
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



