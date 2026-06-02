'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { projectApi } from '@/lib/api/projects';

const StatusBadge = ({ status }: { status: string }) => {
  const styles: Record<string, string> = {
    COMPLETED: 'bg-green-100 text-green-800',
    RUNNING:   'bg-brand-100 text-brand-800',
    FAILED:    'bg-red-100 text-red-800',
    CREATED:   'bg-gray-100 text-gray-600',
    SUBMITTED: 'bg-indigo-100 text-indigo-800',
    PENDING:   'bg-yellow-100 text-yellow-800',
  };
  const cls = styles[status] ?? 'bg-gray-100 text-gray-600';
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls}`}>
      {status}
    </span>
  );
};

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}

export default function ProjectPage() {
  const params = useParams<{ projectNumber: string }>();
  const projectNumber = Number(params.projectNumber);

  const { data: datasetsData, isLoading: datasetsLoading } = useQuery({
    queryKey: ['project-recent-datasets', projectNumber],
    queryFn: () => projectApi.getProjectDatasets(projectNumber, { page: 1, per: 8 }),
  });

  const { data: jobsData, isLoading: jobsLoading } = useQuery({
    queryKey: ['project-recent-jobs', projectNumber],
    queryFn: () => projectApi.getProjectJobs(projectNumber, { page: 1, per: 8 }),
  });

  const totalDatasets = datasetsData?.pagination.total_count;
  const totalJobs = jobsData?.pagination.total_count;

  return (
    <div className="container mx-auto px-6 py-8">

      {/* Header */}
      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Project {projectNumber}</h1>
          <p className="text-sm text-gray-500 mt-1">
            {totalDatasets != null ? `${totalDatasets} dataset${totalDatasets !== 1 ? 's' : ''}` : '—'}
            {' · '}
            {totalJobs != null ? `${totalJobs} job${totalJobs !== 1 ? 's' : ''}` : '—'}
          </p>
        </div>
        <div className="flex gap-2">
          <Link
            href={`/projects/${projectNumber}/datasets/import`}
            className="px-3 py-1.5 text-sm bg-brand-600 text-white rounded-md hover:bg-brand-700 transition-colors"
          >
            Import Dataset
          </Link>
          <Link
            href={`/files/p${projectNumber}`}
            className="px-3 py-1.5 text-sm border border-gray-300 text-gray-700 rounded-md hover:bg-gray-50 transition-colors"
          >
            Browse Files
          </Link>
        </div>
      </div>

      {/* Two-column layout */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">

        {/* Recent Datasets */}
        <div className="bg-white rounded-lg border border-gray-200">
          <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
            <h2 className="font-semibold text-gray-800">Recent Datasets</h2>
            <Link href={`/projects/${projectNumber}/datasets?view=tree`} className="text-xs text-brand-600 hover:underline">
              View all →
            </Link>
          </div>

          {datasetsLoading ? (
            <div className="px-5 py-8 text-center text-sm text-gray-400">Loading…</div>
          ) : !datasetsData?.datasets.length ? (
            <div className="px-5 py-8 text-center text-sm text-gray-400">No datasets yet</div>
          ) : (
            <ul className="divide-y divide-gray-50">
              {datasetsData.datasets.map((ds) => (
                <li key={ds.id} className="px-5 py-3 hover:bg-gray-50 transition-colors">
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <Link
                        href={`/projects/${projectNumber}/datasets/${ds.id}`}
                        className="text-sm font-medium text-brand-700 hover:underline truncate block"
                      >
                        {ds.name}
                      </Link>
                      <p className="text-xs text-gray-400 mt-0.5">
                        {ds.app_name ?? 'imported'}
                        {ds.samples_count != null ? ` · ${ds.completed_samples ?? 0}/${ds.samples_count} samples` : ''}
                      </p>
                    </div>
                    <span className="text-xs text-gray-400 whitespace-nowrap shrink-0">
                      {timeAgo(ds.created_at)}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Recent Jobs */}
        <div className="bg-white rounded-lg border border-gray-200">
          <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
            <h2 className="font-semibold text-gray-800">Recent Jobs</h2>
            <Link href={`/projects/${projectNumber}/jobs`} className="text-xs text-brand-600 hover:underline">
              View all →
            </Link>
          </div>

          {jobsLoading ? (
            <div className="px-5 py-8 text-center text-sm text-gray-400">Loading…</div>
          ) : !jobsData?.jobs.length ? (
            <div className="px-5 py-8 text-center text-sm text-gray-400">No jobs yet</div>
          ) : (
            <ul className="divide-y divide-gray-50">
              {jobsData.jobs.map((job) => (
                <li key={job.id} className="px-5 py-3 hover:bg-gray-50 transition-colors">
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <StatusBadge status={job.status} />
                        {job.dataset ? (
                          <Link
                            href={`/projects/${projectNumber}/datasets/${job.dataset.id}`}
                            className="text-sm font-medium text-gray-700 hover:underline truncate"
                          >
                            {job.dataset.name}
                          </Link>
                        ) : (
                          <span className="text-sm text-gray-400">—</span>
                        )}
                      </div>
                      <p className="text-xs text-gray-400 mt-0.5">by {job.user}</p>
                    </div>
                    <span className="text-xs text-gray-400 whitespace-nowrap shrink-0">
                      {timeAgo(job.created_at)}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>

      </div>
    </div>
  );
}
