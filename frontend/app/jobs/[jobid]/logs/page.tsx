'use client';

import { useParams } from 'next/navigation';
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { jobApi } from '@/lib/api';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';
import { useLastProjectNumber } from '@/lib/hooks';
import LogContent, { extractIssues, LogIssue } from './LogContent';

type Tab = 'stderr' | 'stdout' | 'issues';

function IssuesTab({ issues }: { issues: LogIssue[] }) {
  if (issues.length === 0) {
    return <p className="text-gray-500 p-4 text-sm font-mono">No warnings or errors found.</p>;
  }

  const issueColors = { warn: 'text-amber-400', error: 'text-red-400' };
  const sourceLabel = { out: 'stdout', err: 'stderr' };
  const sourcePillColors = { out: 'bg-gray-700 text-gray-400', err: 'bg-gray-800 text-gray-500' };

  return (
    <div className="p-4 font-mono text-sm overflow-x-auto">
      {issues.map((issue, i) => (
        <div key={i} className="flex items-start gap-2 leading-5 mb-0.5">
          <span className={`shrink-0 mt-0.5 text-xs px-1.5 py-0 rounded ${sourcePillColors[issue.source]}`}>
            {sourceLabel[issue.source]}
          </span>
          <span className={`whitespace-pre-wrap break-all ${issueColors[issue.kind]}`}>
            {issue.line}
          </span>
        </div>
      ))}
    </div>
  );
}

export default function JobLogsPage() {
  const params = useParams<{ jobid: string }>();
  const jobId = Number(params.jobid);
  const [activeTab, setActiveTab] = useState<Tab>('stderr');

  const { data: job, isLoading: jobLoading } = useQuery({
    queryKey: ['job', jobId],
    queryFn: () => jobApi.getJob(jobId),
    enabled: !!jobId,
    staleTime: 30_000,
  });

  const { data: logs, isLoading: logsLoading, error } = useQuery({
    queryKey: ['job-logs', jobId],
    queryFn: () => jobApi.getJobLogs(jobId),
    enabled: !!jobId,
    staleTime: 30_000,
  });

  const isLoading = jobLoading || logsLoading;
  const projectNumber = useLastProjectNumber(job?.project_number);

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

  const stderr = logs?.stderr ?? '';
  const stdout = logs?.stdout ?? '';

  const issues: LogIssue[] = [
    ...extractIssues(stderr, 'err'),
    ...extractIssues(stdout, 'out'),
  ];

  const tabs: { id: Tab; label: string; path?: string | null }[] = [
    { id: 'stderr', label: 'Execution Log', path: job?.stderr_path },
    { id: 'stdout', label: 'Output',        path: job?.stdout_path },
    { id: 'issues', label: `Warnings & Errors${issues.length > 0 ? ` (${issues.length})` : ''}` },
  ];
  const activeTabPath = tabs.find(t => t.id === activeTab)?.path ?? null;

  return (
    <div className="container mx-auto px-6 py-8">

      <Breadcrumbs items={[
        ...(projectNumber ? [
          { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
          { label: 'Jobs', href: `/projects/${projectNumber}/jobs` },
        ] : []),
        { label: `Job ${jobId}` },
        { label: 'Logs', active: true },
      ]} />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Job {jobId} — Logs</h1>
        <button
          onClick={() => window.history.back()}
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          Back
        </button>
      </div>

      <div className="bg-gray-900 rounded-lg overflow-hidden">
        {/* Tab bar */}
        <div className="border-b border-gray-700">
          <div className="flex items-center">
            {tabs.map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-6 py-3 text-base font-semibold border-b-2 transition-colors ${
                  activeTab === tab.id
                    ? 'border-brand-500 text-white'
                    : 'border-transparent text-gray-500 hover:text-gray-300'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>
          {activeTabPath && (
            <div className="px-4 py-1.5 text-xs text-gray-500 font-mono break-all">{activeTabPath}</div>
          )}
        </div>

        {/* Tab content */}
        {activeTab === 'stderr' && <LogContent content={stderr} empty="No execution log available." />}
        {activeTab === 'stdout' && <LogContent content={stdout} empty="No output available." />}
        {activeTab === 'issues' && <IssuesTab issues={issues} />}
      </div>

    </div>
  );
}
