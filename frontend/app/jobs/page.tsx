'use client';

import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import { jobApi } from '@/lib/api';
import { usePagination, useSearch } from '@/lib/hooks';

const StatusBadge = ({ status }: { status: string }) => {
  const getStatusStyles = (status: string) => {
    switch (status) {
      case 'COMPLETED':
        return 'bg-green-100 text-green-800';
      case 'RUNNING':
        return 'bg-brand-100 text-brand-800';
      case 'FAILED':
        return 'bg-red-100 text-red-800';
      case 'CANCELLED+':
        return 'bg-gray-100 text-gray-800';
      case 'CREATED':
        return 'bg-gray-100 text-gray-800';
      case 'SUBMITTED':
        return 'bg-indigo-100 text-indigo-800';
      case 'PENDING':
        return 'bg-yellow-100 text-yellow-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  return (
    <span className={`px-2 py-1 text-xs font-medium rounded-full ${getStatusStyles(status)}`}>
      {status}
    </span>
  );
};

const formatDateTime = (dateString: string) => {
  return new Date(dateString).toLocaleString();
};

const formatDuration = (startTime: string, endTime?: string) => {
  if (!endTime) return 'Running...';

  const start = new Date(startTime);
  const end = new Date(endTime);
  const diffMs = end.getTime() - start.getTime();
  const diffMinutes = Math.floor(diffMs / 60000);
  const diffSeconds = Math.floor((diffMs % 60000) / 1000);

  if (diffMinutes > 0) {
    return `${diffMinutes}m ${diffSeconds}s`;
  }
  return `${diffSeconds}s`;
};

export default function AllJobsPage() {
  // Pagination with shared hook
  const { page, per, goToPage, changePerPage } = usePagination();

  // Filters using search hooks
  const { searchQuery: statusParam, localQuery: statusLocal, setLocalQuery: setStatusLocal, onSubmit } = useSearch('status');
  const { searchQuery: userParam, localQuery: userLocal, setLocalQuery: setUserLocal } = useSearch('user');
  const { searchQuery: datasetNameParam, localQuery: datasetNameLocal, setLocalQuery: setDatasetNameLocal } = useSearch('dataset_name');

  // Build API parameters for backend filtering
  const apiParams = useMemo(() => {
    const params: { page: number; per: number; status?: string; user?: string; dataset_name?: string } = { page, per };
    if (statusParam) params.status = statusParam;
    if (userParam) params.user = userParam;
    if (datasetNameParam) params.dataset_name = datasetNameParam;
    return params;
  }, [page, per, statusParam, userParam, datasetNameParam]);

  const { data: jobsData, isLoading, error } = useQuery({
    queryKey: ['all-jobs', apiParams],
    queryFn: () => jobApi.getAllJobs(apiParams),
    staleTime: 30_000,
  });

  // Use backend pagination and filtering data directly
  const jobs = jobsData?.jobs || [];
  const total = jobsData?.pagination.total_count || 0;
  const totalPages = jobsData?.pagination.total_pages || 0;
  const startIndex = (page - 1) * per + Math.min(1, total);
  const endIndex = Math.min(page * per, total);

  const clearFilters = () => {
    setStatusLocal('');
    setUserLocal('');
    setDatasetNameLocal('');
    // Trigger URL update
    const url = new URL(window.location.href);
    url.searchParams.delete('status');
    url.searchParams.delete('user');
    url.searchParams.delete('dataset_name');
    url.searchParams.set('page', '1');
    window.history.pushState({}, '', url.toString());
    window.location.reload();
  };

  if (isLoading) return (
    <div className="container mx-auto px-6 py-8">
      <div className="animate-pulse">
        <div className="h-8 bg-gray-200 rounded w-64 mb-6"></div>
        <div className="overflow-x-auto">
          <div className="min-w-full border rounded-lg">
            <div className="bg-gray-100 border-b">
              <div className="flex">
                {['ID', 'Status', 'User', 'Dataset', 'Script', 'Logs', 'Duration', 'Started'].map((header, i) => (
                  <div key={i} className="p-3 border-r flex-1">
                    <div className="h-4 bg-gray-300 rounded w-16"></div>
                  </div>
                ))}
              </div>
            </div>
            {[...Array(3)].map((_, i) => (
              <div key={i} className="border-b">
                <div className="flex">
                  {[...Array(8)].map((_, j) => (
                    <div key={j} className="p-3 border-r flex-1">
                      <div className="h-4 bg-gray-200 rounded w-20"></div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );

  if (error) return (
    <div className="container mx-auto px-6 py-8">
      <div className="text-center py-12">
        <div className="text-red-600 text-lg font-medium mb-2">Failed to load jobs</div>
        <p className="text-gray-500 mb-4">There was an error loading the jobs.</p>
      </div>
    </div>
  );

  // Status options for dropdown
  const statusOptions = [
    { value: '', label: 'All' },
    { value: 'COMPLETED', label: 'Completed' },
    { value: 'RUNNING', label: 'Running' },
    { value: 'FAILED', label: 'Failed' },
    { value: 'CANCELLED+', label: 'Cancelled' },
    { value: 'CREATED', label: 'Created' },
    { value: 'SUBMITTED', label: 'Submitted' },
    { value: 'PENDING', label: 'Pending' },
  ];

  return (
    <div className="container mx-auto px-6 py-8">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">All Jobs</h1>
        <button
          onClick={() => window.history.back()}
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          Back
        </button>
      </div>

      <form onSubmit={onSubmit} className="mb-3 space-y-3">
        {/* First row: Entries per page */}
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <label className="text-sm text-gray-600">Show</label>
            <select
              value={per}
              onChange={(e) => changePerPage(Number(e.target.value))}
              className="border border-gray-300 rounded-md px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent"
            >
              <option value={10}>10</option>
              <option value={25}>25</option>
              <option value={50}>50</option>
              <option value={100}>100</option>
            </select>
            <span className="text-sm text-gray-600">entries</span>
          </div>
        </div>

        {/* Second row: Filters */}
        <div className="flex items-center gap-4 flex-wrap">
          <div className="flex items-center gap-2">
            <label className="text-sm text-gray-600">Status:</label>
            <select
              value={statusLocal}
              onChange={(e) => setStatusLocal(e.target.value)}
              className="border border-gray-300 rounded-md px-2 py-1.5 text-sm min-w-32 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent"
            >
              {statusOptions.map(option => (
                <option key={option.value} value={option.value}>{option.label}</option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2">
            <label className="text-sm text-gray-600">User:</label>
            <input
              value={userLocal}
              onChange={(e) => setUserLocal(e.target.value)}
              placeholder="Filter by user..."
              className="border border-gray-300 rounded-md px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent"
            />
          </div>

          <div className="flex items-center gap-2">
            <label className="text-sm text-gray-600">Dataset:</label>
            <input
              value={datasetNameLocal}
              onChange={(e) => setDatasetNameLocal(e.target.value)}
              placeholder="Filter by dataset name..."
              className="border border-gray-300 rounded-md px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent"
            />
          </div>

          <button
            type="submit"
            className="px-3 py-1.5 text-sm font-medium text-white bg-brand-600 border border-brand-600 rounded-md hover:bg-brand-700 transition-colors"
          >
            Apply Filters
          </button>

          <button
            type="button"
            onClick={clearFilters}
            className="px-3 py-1.5 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 transition-colors"
          >
            Clear Filters
          </button>
        </div>
      </form>

      <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
        <div className="overflow-x-auto">
        <table className="min-w-full">
          <thead className="bg-brand-300">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-700 uppercase tracking-wider border-b border-r border-brand-400/30">
                Job ID
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-700 uppercase tracking-wider border-b border-r border-brand-400/30">
                Status
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-700 uppercase tracking-wider border-b border-r border-brand-400/30">
                User
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-700 uppercase tracking-wider border-b border-r border-brand-400/30 max-w-48">
                Next Dataset
              </th>
              <th className="px-3 py-2 text-center text-xs font-medium text-gray-700 uppercase tracking-wider border-b border-r border-brand-400/30">
                Script
              </th>
              <th className="px-3 py-2 text-center text-xs font-medium text-gray-700 uppercase tracking-wider border-b border-r border-brand-400/30">
                Logs
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-700 uppercase tracking-wider border-b border-r border-brand-400/30">
                Duration
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-700 uppercase tracking-wider border-b border-brand-400/30">
                Started
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {jobs.map((job) => (
              <tr key={job.id} className="hover:bg-brand-50 transition-colors">
                <td className="px-3 py-1.5 text-sm font-medium text-gray-900 border-r border-gray-200">
                  {job.id}
                </td>
                <td className="px-3 py-1.5 text-sm border-r border-gray-200">
                  <StatusBadge status={job.status} />
                </td>
                <td className="px-3 py-1.5 text-sm text-gray-900 border-r border-gray-200">
                  {job.user}
                </td>
                <td className="px-3 py-1.5 text-sm border-r border-gray-200 max-w-48">
                  {job.dataset ? (
                    <span
                      className="font-medium truncate block"
                      title={`${job.dataset.name} (ID: ${job.dataset.id})`}
                    >
                      {job.dataset.name} <span className="text-gray-400 font-normal">#{job.dataset.id}</span>
                    </span>
                  ) : (
                    <span className="text-gray-400">-</span>
                  )}
                </td>
                <td className="px-3 py-1.5 text-sm border-r border-gray-200 text-center">
                  <Link
                    href={`/jobs/${job.id}/script`}
                    className="inline-flex items-center px-3 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded-full hover:bg-gray-200 transition-colors whitespace-nowrap"
                  >
                    Show Script
                  </Link>
                </td>
                <td className="px-3 py-1.5 text-sm border-r border-gray-200 text-center">
                  <Link
                    href={`/jobs/${job.id}/logs`}
                    className="inline-flex items-center px-3 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded-full hover:bg-gray-200 transition-colors whitespace-nowrap"
                  >
                    Show Logs
                  </Link>
                </td>
                <td className="px-3 py-1.5 text-sm text-gray-900 border-r border-gray-200">
                  {job.time.start_time ? formatDuration(job.time.start_time, job.time.end_time) : '-'}
                </td>
                <td className="px-3 py-1.5 text-sm text-gray-900">
                  {job.time.start_time ? formatDateTime(job.time.start_time) : '-'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      </div>

      {jobs.length === 0 && (
        <div className="text-center py-12">
          <div className="text-gray-500 text-lg mb-2">No jobs found</div>
          <p className="text-gray-400">Try adjusting your filters.</p>
        </div>
      )}

      <div className="mt-3 flex items-center justify-between gap-2">
        <div className="text-sm text-gray-600">Showing {startIndex} to {endIndex} of {total} entries</div>
        <div className="flex items-center gap-2">
          <button
            disabled={page <= 1}
            onClick={() => goToPage(page - 1)}
            className="px-3 py-1.5 text-sm font-medium border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            Prev
          </button>
          <span className="text-sm text-gray-700">Page {page} / {totalPages}</span>
          <button
            disabled={page >= totalPages}
            onClick={() => goToPage(page + 1)}
            className="px-3 py-1.5 text-sm font-medium border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            Next
          </button>
        </div>
      </div>
    </div>
  );
}
