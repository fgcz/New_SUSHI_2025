"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useState, useEffect } from "react";
import { JobSubmissionRequest } from "@/lib/types";
import Breadcrumbs from '@/lib/ui/Breadcrumbs';
import { useDatasetBase, useJobSubmission } from '@/lib/hooks';

interface StoredJobData {
  projectNumber: number;
  datasetId: number;
  appName: string;
  nextDataset: {
    name: string;
    comment?: string;
  };
  parameters: Record<string, any>;
}

export default function ConfirmJobPage() {
  const params = useParams<{
    projectNumber: string;
    datasetId: string;
    appName: string;
  }>();
  const router = useRouter();
  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);
  const appName = params.appName;

  const [jobData, setJobData] = useState<StoredJobData | null>(null);
  const [dataLoadError, setDataLoadError] = useState<string | null>(null);

  // Use existing hook for dataset data
  const { dataset, isLoading: isDatasetLoading, error: datasetError, notFound: datasetNotFound } = useDatasetBase(datasetId);

  // Use custom hook for job submission
  const { submitJob, isSubmitting, error: submitError, success: submitSuccess } = useJobSubmission();

  // Load data from localStorage on mount
  useEffect(() => {
    try {
      const storedData = localStorage.getItem('sushi_job_submission_data');
      if (!storedData) {
        setDataLoadError('No job data found. Please go back and fill out the form.');
        return;
      }

      const parsedData: StoredJobData = JSON.parse(storedData);
      
      // Validate that the stored data matches current URL params
      if (
        parsedData.projectNumber !== projectNumber ||
        parsedData.datasetId !== datasetId ||
        parsedData.appName !== appName
      ) {
        setDataLoadError('Job data does not match current page. Please go back and resubmit.');
        return;
      }

      setJobData(parsedData);
    } catch (error) {
      setDataLoadError('Failed to load job data. Please go back and try again.');
      console.error('Error loading job data from localStorage:', error);
    }
  }, [projectNumber, datasetId, appName]);

  const handleConfirmSubmission = async () => {
    if (!jobData) return;

    const submissionData: JobSubmissionRequest = {
      project_number: jobData.projectNumber,
      dataset_id: jobData.datasetId,
      app_name: jobData.appName,
      next_dataset: jobData.nextDataset,
      parameters: jobData.parameters,
    };

    await submitJob(submissionData);
  };

  // Handle successful submission
  useEffect(() => {
    if (submitSuccess) {
      // Clear localStorage after successful submission
      localStorage.removeItem('sushi_job_submission_data');
      // Navigate to jobs page or dataset page
      router.push(`/projects/${projectNumber}/datasets/${datasetId}`);
    }
  }, [submitSuccess, router, projectNumber, datasetId]);

  const handleMockRun = () => {
    // TODO: Implement mock run functionality
    console.log('Mock run requested with data:', jobData);
    alert('Mock run functionality not yet implemented');
  };

  const handleGoBack = () => {
    router.back();
  };

  if (isDatasetLoading) {
    return (
      <div className="container mx-auto px-6 py-8">
        <div className="animate-pulse space-y-4">
          <div className="h-8 bg-gray-200 rounded w-1/3"></div>
          <div className="h-4 bg-gray-200 rounded w-2/3"></div>
          <div className="space-y-2">
            <div className="h-4 bg-gray-200 rounded"></div>
            <div className="h-4 bg-gray-200 rounded w-5/6"></div>
          </div>
        </div>
      </div>
    );
  }

  if (datasetError) {
    return (
      <div className="container mx-auto px-6 py-8">
        <div className="text-center py-12">
          <div className="text-red-600 text-lg font-medium mb-2">
            Failed to load dataset
          </div>
          <p className="text-gray-500 mb-4">
            There was an error loading the dataset information.
          </p>
          <Link
            href={`/projects/${projectNumber}/datasets`}
            className="text-blue-600 hover:underline"
          >
            ← Back to Datasets
          </Link>
        </div>
      </div>
    );
  }

  if (datasetNotFound || !dataset) {
    return (
      <div className="container mx-auto px-6 py-8">
        <h1 className="text-2xl font-bold mb-4 text-red-600">
          Dataset Not Found
        </h1>
        <p className="text-gray-700 mb-6">
          Dataset {datasetId} was not found in project {projectNumber}.
        </p>
        <Link
          href={`/projects/${projectNumber}/datasets`}
          className="text-blue-600 hover:underline"
        >
          ← Back to Datasets
        </Link>
      </div>
    );
  }

  if (dataLoadError) {
    return (
      <div className="container mx-auto px-6 py-8">
        <h1 className="text-2xl font-bold mb-4 text-red-600">
          No Job Data Found
        </h1>
        <p className="text-gray-700 mb-6">{dataLoadError}</p>
        <Link
          href={`/projects/${projectNumber}/datasets/${datasetId}/run-application/${appName}`}
          className="text-blue-600 hover:underline"
        >
          ← Back to Application Form
        </Link>
      </div>
    );
  }

  if (!jobData) {
    return (
      <div className="container mx-auto px-6 py-8">
        <div className="text-center">
          <div className="text-gray-400 text-lg mb-2">⚙️</div>
          <p className="text-gray-500">Loading job data...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-6 py-8">
      <Breadcrumbs items={[
        { label: 'Projects', href: '/projects' },
        { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
        { label: 'Datasets', href: `/projects/${projectNumber}/datasets` },
        { label: dataset.name, href: `/projects/${projectNumber}/datasets/${datasetId}` },
        { label: `Run ${appName}`, href: `/projects/${projectNumber}/datasets/${datasetId}/run-application/${appName}` },
        { label: 'Confirm', active: true }
      ]} />

      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold">Confirm Job Submission</h1>
          <p className="text-gray-600 mt-1">Application: {appName}</p>
          <p className="text-gray-600 mt-1">Dataset: {dataset.name}</p>
        </div>
        <button
          onClick={handleGoBack}
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          ← Back to Edit
        </button>
      </div>

      <div className="space-y-6">
        {/* NextDataset Information */}
        <div className="bg-white border rounded-lg overflow-hidden">
          <div className="bg-gray-50 px-6 py-3 border-b">
            <h3 className="text-lg font-semibold">Result Dataset</h3>
          </div>
          <div className="p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <dt className="text-sm font-medium text-gray-500">Name</dt>
                <dd className="mt-1 text-sm text-gray-900">{jobData.nextDataset.name}</dd>
              </div>
              {jobData.nextDataset.comment && (
                <div>
                  <dt className="text-sm font-medium text-gray-500">Comment</dt>
                  <dd className="mt-1 text-sm text-gray-900">{jobData.nextDataset.comment}</dd>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Parameters */}
        <div className="bg-white border rounded-lg overflow-hidden">
          <div className="bg-gray-50 px-6 py-3 border-b">
            <h3 className="text-lg font-semibold">Application Parameters</h3>
          </div>
          <div className="p-6">
            {Object.keys(jobData.parameters).length === 0 ? (
              <p className="text-gray-500 italic">No parameters configured</p>
            ) : (
              <dl className="space-y-4">
                {Object.entries(jobData.parameters).map(([key, value]) => (
                  <div key={key} className="flex flex-col sm:flex-row sm:items-start">
                    <dt className="text-sm font-medium text-gray-500 sm:w-1/3 sm:flex-shrink-0">
                      {key}
                    </dt>
                    <dd className="mt-1 sm:mt-0 sm:ml-4 text-sm text-gray-900">
                      {typeof value === 'object' ? (
                        <pre className="bg-gray-100 p-2 rounded text-xs overflow-x-auto">
                          {JSON.stringify(value, null, 2)}
                        </pre>
                      ) : (
                        <span className="break-words">{String(value)}</span>
                      )}
                    </dd>
                  </div>
                ))}
              </dl>
            )}
          </div>
        </div>

        {/* Error/Success Messages */}
        {submitError && (
          <div className="p-4 bg-red-50 border border-red-200 rounded-md">
            <div className="flex">
              <div className="text-red-600 text-sm">
                <strong>Submission failed:</strong> {submitError}
              </div>
            </div>
          </div>
        )}

        {submitSuccess && (
          <div className="p-4 bg-green-50 border border-green-200 rounded-md">
            <div className="flex">
              <div className="text-green-600 text-sm">
                <strong>Success:</strong> Job submitted successfully! Redirecting...
              </div>
            </div>
          </div>
        )}

        {/* Action Buttons */}
        <div className="flex flex-col sm:flex-row gap-4 pt-4">
          <button
            onClick={handleConfirmSubmission}
            disabled={isSubmitting}
            className="flex-1 px-6 py-3 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors duration-200 font-medium disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isSubmitting ? "Submitting Job..." : "Confirm & Submit Job"}
          </button>
          
          <button
            onClick={handleMockRun}
            disabled={isSubmitting}
            className="flex-1 px-6 py-3 bg-gray-600 text-white rounded-md hover:bg-gray-700 transition-colors duration-200 font-medium disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Mock Run (Preview)
          </button>
        </div>

        <div className="text-center">
          <button
            onClick={handleGoBack}
            className="text-gray-600 hover:text-gray-800 text-sm"
          >
            Need to make changes? Go back to edit the form
          </button>
        </div>
      </div>
    </div>
  );
}