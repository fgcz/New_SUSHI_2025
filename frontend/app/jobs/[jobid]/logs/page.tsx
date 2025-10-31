'use client';

import { useParams } from 'next/navigation';
import Link from 'next/link';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';

export default function JobLogsPage() {
  const params = useParams<{ jobid: string }>();
  const jobId = params.jobid;

  const hardcodedLogs = `2024-10-08 09:15:30,123 - INFO - Starting job ${jobId} - Customer Analytics Q3
2024-10-08 09:15:30,125 - INFO - Initializing data processing pipeline
2024-10-08 09:15:30,126 - INFO - Loading data from /data/customer_data_q3.csv
2024-10-08 09:15:31,456 - INFO - Successfully loaded 15,247 records
2024-10-08 09:15:31,457 - INFO - Data validation passed: 15,247 valid records, 0 invalid records
2024-10-08 09:15:31,458 - INFO - Starting analytics processing
2024-10-08 09:15:31,890 - INFO - Calculating customer metrics for 15,247 customers
2024-10-08 09:15:32,234 - INFO - Customer segmentation complete:
2024-10-08 09:15:32,235 - INFO -   Bronze: 8,123 customers (53.3%)
2024-10-08 09:15:32,236 - INFO -   Silver: 4,567 customers (29.9%)
2024-10-08 09:15:32,237 - INFO -   Gold: 2,234 customers (14.7%)
2024-10-08 09:15:32,238 - INFO -   Platinum: 323 customers (2.1%)
2024-10-08 09:15:32,567 - INFO - Generating summary statistics
2024-10-08 09:15:33,123 - INFO - Summary statistics generated successfully
2024-10-08 09:15:33,456 - INFO - Analytics processing completed
2024-10-08 09:15:33,789 - INFO - Saving processed data to /output/analytics_results_${jobId}.csv
2024-10-08 09:15:34,234 - INFO - Data export completed: 15,247 records written
2024-10-08 09:15:34,567 - INFO - Generating visualization charts
2024-10-08 09:15:35,123 - INFO - Chart generation completed: 5 charts saved
2024-10-08 09:15:35,456 - INFO - Results saved to /output/analytics_results_${jobId}.csv
2024-10-08 09:15:35,789 - INFO - Performance metrics:
2024-10-08 09:15:35,790 - INFO -   Total execution time: 5.667 seconds
2024-10-08 09:15:35,791 - INFO -   Records processed per second: 2,691
2024-10-08 09:15:35,792 - INFO -   Memory usage: 234.5 MB peak
2024-10-08 09:15:35,793 - INFO -   CPU usage: 87% average
2024-10-08 09:15:35,794 - INFO - Job completed successfully
2024-10-08 09:15:35,795 - INFO - Cleanup: temporary files removed
2024-10-08 09:15:35,796 - INFO - Exit code: 0`;
  const projectNumber = 12312;
  return (
    <div className="container mx-auto px-6 py-8">
  
      <Breadcrumbs items={[
        { label: 'Projects', href: '/projects' },
        { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
        { label: 'Jobs', href: `/projects/${projectNumber}/jobs` },
        { label: `Job ${jobId}` },
        { label: "Logs", active: true }
      ]} />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Job {jobId} - Execution Logs</h1>
        <button 
          onClick={() => window.history.back()} 
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          ← Back
        </button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <div className="px-4 py-3 bg-gray-50 border-b border-gray-200">
          <h2 className="text-lg font-medium text-gray-900">Execution Log</h2>
          <p className="text-sm text-gray-500">Real-time job execution output</p>
        </div>
        <div className="p-0 bg-black">
          <pre style={{wordWrap: 'break-word', whiteSpace: 'pre-wrap'}} className="text-sm text-green-400 p-4 overflow-x-auto font-mono">
            {hardcodedLogs}
          </pre>
        </div>
      </div>

      <div className="mt-4 text-sm text-gray-600">
        Log updated: {new Date().toLocaleString()}
      </div>
    </div>
  );
}
