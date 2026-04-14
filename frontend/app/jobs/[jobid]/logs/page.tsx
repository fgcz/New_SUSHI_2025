'use client';

import { useParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { jobApi } from '@/lib/api';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';

export default function JobLogsPage() {
  const params = useParams<{ jobid: string }>();
  const jobId = Number(params.jobid);

  const { data: job, isLoading: jobLoading } = useQuery({
    queryKey: ['job', jobId],
    queryFn: () => jobApi.getJob(jobId),
    enabled: !!jobId,
    staleTime: 30_000,
  });

  const { data: logs, isLoading: logsLoading, error, refetch } = useQuery({
    queryKey: ['job-logs', jobId],
    queryFn: () => jobApi.getJobLogs(jobId),
    enabled: !!jobId,
    staleTime: 30_000,
  });

  const isLoading = jobLoading || logsLoading;
  const projectNumber = job?.project_number ?? null;

  if (isLoading) {
    return (
      <div className="container mx-auto px-6 py-8">
        <div className="animate-pulse">
          <div className="h-8 bg-gray-200 rounded w-64 mb-6"></div>
          <div className="bg-white border border-gray-200 rounded-lg p-8">
            <div className="flex items-center justify-center">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-500"></div>
              <span className="ml-3 text-gray-600">Loading logs...</span>
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="container mx-auto px-6 py-8">
        <div className="text-center py-12">
          <div className="text-red-600 text-lg font-medium mb-2">Failed to load logs</div>
          <p className="text-gray-500">There was an error loading the job logs.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-6 py-8">

      <Breadcrumbs items={[
        { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
        { label: 'Jobs', href: `/projects/${projectNumber}/jobs` },
        { label: `Job ${jobId}` },
        { label: "Logs", active: true }
      ]} />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Job {jobId} - Execution Logs</h1>
        <div className="flex gap-2">
          <button
            onClick={() => refetch()}
            className="px-4 py-2 text-sm font-medium text-white bg-brand-600 border border-brand-600 rounded-md hover:bg-brand-700"
          >
            Refresh
          </button>
          <button
            onClick={() => window.history.back()}
            className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
          >
            Back
          </button>
        </div>
      </div>

      {/* STDOUT */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden mb-4">
        <div className="px-4 py-3 bg-gray-800 border-b border-gray-700 flex items-center gap-2">
          <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-500 text-white">
            STDOUT
          </span>
          <span className="text-sm text-gray-300">Standard Output</span>
        </div>
        <div className="bg-gray-900">
          <pre style={{wordWrap: 'break-word', whiteSpace: 'pre-wrap'}} className="text-sm text-green-400 p-4 overflow-x-auto font-mono max-h-96 overflow-y-auto">
            {logs?.stdout || 'No output'}
          </pre>
        </div>
      </div>

      {/* STDERR */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <div className="px-4 py-3 bg-gray-800 border-b border-gray-700 flex items-center gap-2">
          <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-500 text-black">
            STDERR
          </span>
          <span className="text-sm text-gray-300">Standard Error</span>
        </div>
        <div className="bg-gray-900">
          <pre style={{wordWrap: 'break-word', whiteSpace: 'pre-wrap'}} className="text-sm text-yellow-400 p-4 overflow-x-auto font-mono max-h-96 overflow-y-auto">
            {logs?.stderr || 'No errors'}
          </pre>
        </div>
      </div>

      <div className="mt-4 text-sm text-gray-500">
        Last fetched: {new Date().toLocaleString()}
      </div>
    </div>
  );
}
