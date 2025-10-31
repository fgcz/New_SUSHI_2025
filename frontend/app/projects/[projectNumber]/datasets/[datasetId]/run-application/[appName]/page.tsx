"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useState, useEffect } from "react";
import { JobSubmissionRequest, DynamicFormData } from "@/lib/types";
import {
  FormFieldComponent,
  initializeFormData,
} from "@/lib/utils/form-renderer";
import Breadcrumbs from '@/lib/ui/Breadcrumbs';
import { useDatasetBase, useApplicationFormSchema, useJobSubmission } from '@/lib/hooks';
import RunApplicationPageSkeleton from './RunApplicationPageSkeleton';

export default function RunApplicationPage() {
  const params = useParams<{
    projectNumber: string;
    datasetId: string;
    appName: string;
  }>();
  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);
  const appName = params.appName;

  // Use existing hook for dataset data
  const { dataset, isLoading: isDatasetLoading, error: datasetError, notFound: datasetNotFound } = useDatasetBase(datasetId);

  // Use custom hook for form schema
  const {
    data: formConfigData,
    isLoading: isFormConfigLoading,
    error: formConfigError,
  } = useApplicationFormSchema(appName);
  
  const formConfig = formConfigData?.application;

  // Use custom hook for job submission
  const { submitJob, isSubmitting, error: submitError, success: submitSuccess } = useJobSubmission();

  // Form state management (remaining local state)
  const [nextDatasetData, setNextDatasetData] = useState({
    datasetName: `this input will change once dataset name is retrieved`,
    datasetComment: "",
  });
  const [dynamicFormData, setDynamicFormData] = useState<DynamicFormData>({});

  // Update dataset name when data is loaded (timeout kept for debugging loading states)
  useEffect(() => {
    const timeoutId = setTimeout(() => {
      if (dataset) {
        setNextDatasetData((prev) => ({
          ...prev,
          datasetName: `${appName}_${dataset.name}_${new Date().toISOString().slice(0, 10)}`,
        }));
      }
    }, 1000);
    return () => clearTimeout(timeoutId);
  }, [dataset, appName]);

  // Initialize dynamic form data when schema loads
  useEffect(() => {
    if (formConfig?.form_fields) {
      setDynamicFormData(initializeFormData(formConfig.form_fields));
    }
  }, [formConfig]);

  // Form handlers
  const handleInputChange = (
    e: React.ChangeEvent<
      HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement
    >,
  ) => {
    const { name, value } = e.target;
    setNextDatasetData((prev) => ({
      ...prev,
      [name]: value,
    }));
  };

  const handleDynamicFieldChange = (fieldName: string, value: any) => {
    setDynamicFormData((prev) => ({
      ...prev,
      [fieldName]: value,
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!dataset) return;

    const jobData: JobSubmissionRequest = {
      project_number: projectNumber,
      dataset_id: datasetId,
      app_name: appName,
      next_dataset: {
        name: nextDatasetData.datasetName,
        comment: nextDatasetData.datasetComment || undefined,
      },
      parameters: dynamicFormData,
    };

    await submitJob(jobData);
  };

  if (isDatasetLoading || isFormConfigLoading) {
    return <RunApplicationPageSkeleton />;
  }

  if (datasetError || formConfigError)
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

  return (
    <div className="container mx-auto px-6 py-8">

      <Breadcrumbs items={[
        { label: 'Projects', href: '/projects' },
        { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
        { label: 'Datasets', href: `/projects/${projectNumber}/datasets` },
        { label: dataset.name, href: `/projects/${projectNumber}/datasets/${datasetId}`},
        { label: `Run ${appName}`, active: true }
      ]} />

      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold">Run Application: {appName}</h1>
          <p className="text-gray-600 mt-1">Dataset: {dataset.name}</p>
          <p className="text-gray-600 mt-1">
            Description: {formConfig?.description || "Loading application description..."}
          </p>
        </div>
        <Link
          href={`/projects/${projectNumber}/datasets/${datasetId}`}
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
        >
          ← Back to Dataset
        </Link>
      </div>

      <div className="space-y-6">
        {/* NextDataset Section */}
        <div className="bg-white border rounded-lg overflow-hidden">
          <div className="p-6">
            <h3 className="text-lg font-semibold mb-6">NextDataset</h3>

            <div className="space-y-4">
              {/* Dataset Name */}
              <div>
                <label
                  htmlFor="datasetName"
                  className="block text-sm font-medium text-gray-700 mb-2"
                >
                  Name
                </label>
                <input
                  type="text"
                  id="datasetName"
                  name="datasetName"
                  value={nextDatasetData.datasetName}
                  onChange={handleInputChange}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  placeholder={`${appName}_${dataset.name}_${new Date().toISOString().slice(0, 10)}`}
                />
              </div>

              {/* Dataset Comment */}
              <div>
                <label
                  htmlFor="datasetComment"
                  className="block text-sm font-medium text-gray-700 mb-2"
                >
                  Comment
                </label>
                <input
                  type="text"
                  id="datasetComment"
                  name="datasetComment"
                  value={nextDatasetData.datasetComment}
                  onChange={handleInputChange}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  placeholder="Optional comment for the resulting dataset..."
                />
              </div>
            </div>
          </div>
        </div>

        {/* Parameters Section */}
        <div className="bg-white border rounded-lg overflow-hidden">
          <div className="p-6">
            <h3 className="text-lg font-semibold mb-6">Parameters</h3>

            <form onSubmit={handleSubmit} className="space-y-6">
              {/* Dynamic form fields in grid layout */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-6">
                {formConfig?.form_fields?.map((field) => (
                  <FormFieldComponent
                    key={field.name}
                    field={field}
                    value={dynamicFormData[field.name]}
                    onChange={handleDynamicFieldChange}
                  />
                ))}
              </div>

              {/* Error/Success Messages */}
              {submitError && (
                <div className="p-3 bg-red-50 border border-red-200 rounded-md">
                  <p className="text-red-600 text-sm">{submitError}</p>
                </div>
              )}
              {submitSuccess && (
                <div className="p-3 bg-green-50 border border-green-200 rounded-md">
                  <p className="text-green-600 text-sm">
                    Job submitted successfully! Check the console for details.
                  </p>
                </div>
              )}

              {/* Submit button */}
              <div className="pt-4">
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="px-6 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors duration-200 font-medium disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {isSubmitting ? "Submitting..." : "Submit Job"}
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}
