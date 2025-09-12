'use client';

import { useEffect, useMemo, useState } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/lib/api';

export default function ProjectDatasetsPage() {
  const params = useParams<{ projectNumber: string }>();
  const projectNumber = Number(params.projectNumber);
  const searchParams = useSearchParams();
  const router = useRouter();

  // URL-driven parameters
  const page = useMemo(() => Number(searchParams.get('page') || 1), [searchParams]);
  const per = useMemo(() => Number(searchParams.get('per') || 50), [searchParams]);
  const qParam = useMemo(() => searchParams.get('q') || '', [searchParams]);

  // Local input state for search box (debounceは後続タスクで)
  const [qLocal, setQLocal] = useState(qParam);
  useEffect(() => { setQLocal(qParam); }, [qParam]);

  const { data, isLoading, error } = useQuery({
    queryKey: ['datasets', projectNumber, { q: qParam, page, per }],
    queryFn: () => apiClient.getProjectDatasets(projectNumber, { q: qParam, page, per }),
    keepPreviousData: true,
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
    const sp = new URLSearchParams(searchParams);
    if (qLocal) sp.set('q', qLocal); else sp.delete('q');
    sp.set('page', '1');
    router.push(`?${sp.toString()}`);
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

  if (isLoading) return <div className="p-6">Loading datasets...</div>;
  if (error) return <div className="p-6 text-red-600">Failed to load datasets</div>;

  const datasets = data?.datasets ?? [];
  const total = data?.total_count ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / per));
  const allIds = datasets.map((d) => d.id);
  const allSelectedOnPage = allIds.length > 0 && allIds.every((id) => selectedSet.has(id));
  const startIndex = (page - 1) * per + Math.min(1, total);
  const endIndex = Math.min(page * per, total);

  return (
    <div className="container mx-auto px-6 py-8">
      <h1 className="text-2xl font-bold mb-6">Project {projectNumber} - DataSets</h1>

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
    </div>
  );
}



