'use client';

import { useMemo } from 'react';
import { useParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import Link from 'next/link';
import { jobApi } from '@/lib/api/jobs';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';
import { useSearch, usePagination } from '@/lib/hooks';

const StatusBadge = ({ status }: { status: string }) => {
  const getStatusStyles = (status: string) => {
    switch (status) {
      case 'COMPLETED':
        return 'bg-green-100 text-green-800';
      case 'RUNNING':
        return 'bg-blue-100 text-blue-800';
      case 'FAILED':
        return 'bg-red-100 text-red-800';
      case 'CANCELED+':
        return 'bg-gray-100 text-gray-800';
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

export default function ProjectJobsPage() {
  const params = useParams<{ projectNumber: string }>();
  const projectNumber = Number(params.projectNumber);

  // Use custom hooks for state management
  const { searchQuery, localQuery, setLocalQuery, onSubmit } = useSearch();
  const { page, per, goToPage, changePerPage } = usePagination(25); // Default 25 for jobs

  const { data: jobsData, isLoading, error } = useQuery({
    queryKey: ['jobs', projectNumber],
    queryFn: () => jobApi.getJobsList(projectNumber),
    staleTime: 30_000,
  });

  // Duplicate jobs 50 times each to get 150 total jobs
  const allJobs = useMemo(() => {
    if (!jobsData?.jobs) return [];
    const duplicatedJobs = [];
    for (let i = 0; i < 50; i++) {
      jobsData.jobs.forEach((job, index) => {
        duplicatedJobs.push({
          ...job,
          id: 1000 + (i * 3) + index + 1,
          dataset: {
            ...job.dataset,
            name: `${job.dataset.name} #${i + 1}`,
            id: job.dataset.id + i
          }
        });
      });
    }
    return duplicatedJobs;
  }, [jobsData]);

  // Filter jobs based on search query (dataset name)
  const filteredJobs = useMemo(() => {
    if (!searchQuery) return allJobs;
    return allJobs.filter(job => 
      job.dataset.name.toLowerCase().includes(searchQuery.toLowerCase())
    );
  }, [allJobs, searchQuery]);

  // Paginate filtered jobs
  const paginatedJobs = useMemo(() => {
    const startIndex = (page - 1) * per;
    const endIndex = startIndex + per;
    return filteredJobs.slice(startIndex, endIndex);
  }, [filteredJobs, page, per]);

  const total = filteredJobs.length;
  const totalPages = Math.max(1, Math.ceil(total / per));
  const startIndex = (page - 1) * per + Math.min(1, total);
  const endIndex = Math.min(page * per, total);


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
        <p className="text-gray-500 mb-4">There was an error loading the jobs for this project.</p>
      </div>
    </div>
  );

  const jobs = paginatedJobs;

  return (
    <div className="container mx-auto px-6 py-8">

      <Breadcrumbs items={[
        { label: 'Projects', href: '/projects' },
        { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
        { label: "Jobs", active: true }
      ]} />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Project {projectNumber} - Jobs</h1>
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
            <option value={10}>10</option>
            <option value={25}>25</option>
            <option value={50}>50</option>
            <option value={100}>100</option>
          </select>
          <span className="text-sm text-gray-600">entries</span>
        </div>

        <div className="flex items-center gap-2">
          <input 
            value={localQuery} 
            onChange={(e) => setLocalQuery(e.target.value)} 
            placeholder="Search dataset name..." 
            className="border rounded px-3 py-2" 
          />
          <div className="text-xs text-gray-500">Search updates automatically</div>
        </div>
      </form>

      <div className="overflow-x-auto">
        <table className="min-w-full border border-gray-200 rounded-lg">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-b border-r">
                Job ID
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-b border-r">
                Status
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-b border-r">
                User
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-b border-r">
                Dataset
              </th>
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider border-b border-r">
                Script
              </th>
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider border-b border-r">
                Logs
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-b border-r">
                Duration
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-b">
                Started
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {jobs.map((job) => (
              <tr key={job.id} className="hover:bg-gray-50">
                <td className="px-4 py-3 text-sm font-medium text-gray-900 border-r">
                  {job.id}
                </td>
                <td className="px-4 py-3 text-sm border-r">
                  <StatusBadge status={job.status} />
                </td>
                <td className="px-4 py-3 text-sm text-gray-900 border-r">
                  {job.user}
                </td>
                <td className="px-4 py-3 text-sm border-r">
                  <div>
                    <Link 
                      href={`/projects/${projectNumber}/datasets/${job.dataset.id}`}
                      className="text-blue-600 hover:underline font-medium"
                    >
                      {job.dataset.name}
                    </Link>
                    <div className="text-gray-500 text-xs">ID: {job.dataset.id}</div>
                  </div>
                </td>
                <td className="px-4 py-3 text-sm border-r text-center">
                  <Link 
                    href={`/jobs/${job.id}/script`}
                    className="inline-flex items-center px-3 py-1 text-xs font-medium text-blue-700 bg-blue-100 rounded-full hover:bg-blue-200"
                  >
                    Show Script
                  </Link>
                </td>
                <td className="px-4 py-3 text-sm border-r text-center">
                  <Link 
                    href={`/jobs/${job.id}/logs`}
                    className="inline-flex items-center px-3 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded-full hover:bg-gray-200"
                  >
                    Show Logs
                  </Link>
                </td>
                <td className="px-4 py-3 text-sm text-gray-900 border-r">
                  {formatDuration(job.time.start_time, job.time.end_time)}
                </td>
                <td className="px-4 py-3 text-sm text-gray-900">
                  {formatDateTime(job.time.start_time)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {jobs.length === 0 && (
        <div className="text-center py-12">
          <div className="text-gray-500 text-lg mb-2">No jobs found</div>
          <p className="text-gray-400">There are no jobs for this project yet.</p>
        </div>
      )}

      <div className="mt-4 flex items-center justify-between gap-2">
        <div className="text-sm text-gray-600">Showing {startIndex} to {endIndex} of {total} entries</div>
        <div className="flex items-center gap-2">
          <button 
            disabled={page <= 1} 
            onClick={() => goToPage(page - 1)} 
            className="px-3 py-1 border rounded disabled:opacity-50"
          >
            Prev
          </button>
          <span>Page {page} / {totalPages}</span>
          <button 
            disabled={page >= totalPages} 
            onClick={() => goToPage(page + 1)} 
            className="px-3 py-1 border rounded disabled:opacity-50"
          >
            Next
          </button>
        </div>
      </div>
    </div>
  );
}
