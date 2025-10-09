"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { useState, useEffect } from "react";
import { projectApi, jobApi, applicationApi } from "@/lib/api";
import { JobSubmissionRequest, DynamicFormData } from "@/lib/types";
import {
  FormFieldComponent,
  initializeFormData,
} from "@/lib/utils/form-renderer";

export default function RunApplicationPage() {
  const params = useParams<{
    projectNumber: string;
    datasetId: string;
    appName: string;
  }>();
  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);
  const appName = params.appName;

  const {
    data: projectData,
    isLoading: isProjectLoading,
    error: projectError,
  } = useQuery({
    queryKey: ["datasets", projectNumber],
    queryFn: () => projectApi.getProjectDatasets(projectNumber),
    staleTime: 60_000,
  });

  // Fetch dynamic form schema for the application
  const {
    data: formConfig,
    isLoading: isFormConfigLoading,
    error: formConfigError,
  } = useQuery({
    queryKey: ["appForm", appName],
    queryFn: () => applicationApi.getFormSchema(appName),
    staleTime: 60_000,
  });

  // Form state management
  const [nextDatasetData, setNextDatasetData] = useState({
    datasetName: `this input will change once dataset name is retrieved`,
    datasetComment: "",
  });
  const [dynamicFormData, setDynamicFormData] = useState<DynamicFormData>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [submitSuccess, setSubmitSuccess] = useState(false);

  // Update dataset name when data is loaded
  useEffect(() => {
    const timeoutId = setTimeout(() => {
      if (projectData?.datasets) {
        const dataset = projectData.datasets.find((ds) => ds.id === datasetId);
        if (dataset) {
          setNextDatasetData((prev) => ({
            ...prev,
            datasetName: `${appName}_${dataset.name}_${new Date().toISOString().slice(0, 10)}`,
          }));
        }
      }
    }, 1000);
    return () => clearTimeout(timeoutId);
  }, [projectData, datasetId, appName]);

  // Initialize dynamic form data when schema loads
  useEffect(() => {
    if (formConfig?.fields) {
      setDynamicFormData(initializeFormData(formConfig.fields));
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

    if (!projectData?.datasets) return;

    const dataset = projectData.datasets.find((ds) => ds.id === datasetId);
    if (!dataset) return;

    setIsSubmitting(true);
    setSubmitError(null);
    setSubmitSuccess(false);

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

    // Log form data to console
    console.log("Submitting job with data:", jobData);

    try {
      const response = await jobApi.submitJob(jobData);
      console.log("Job submission response:", response);
      setSubmitSuccess(true);
    } catch (error) {
      console.error("Job submission failed:", error);
      setSubmitError("Failed to submit job. Please try again.");
    } finally {
      setIsSubmitting(false);
    }
  };

  if (isProjectLoading || isFormConfigLoading)
    return (
      <div className="container mx-auto px-6 py-8">
        <div className="animate-pulse">
          {/* Breadcrumb skeleton */}
          <div className="h-4 bg-gray-200 rounded w-64 mb-6"></div>

          {/* Title skeleton */}
          <div className="h-8 bg-gray-200 rounded w-96 mb-6"></div>

          {/* Form skeleton */}
          <div className="bg-white border rounded-lg p-6">
            <div className="space-y-6">
              <div className="h-6 bg-gray-200 rounded w-32 mb-4"></div>
              {[...Array(4)].map((_, i) => (
                <div key={i} className="space-y-2">
                  <div className="h-4 bg-gray-200 rounded w-24"></div>
                  <div className="h-10 bg-gray-200 rounded"></div>
                </div>
              ))}
              <div className="h-10 bg-gray-200 rounded w-32"></div>
            </div>
          </div>
        </div>
      </div>
    );

  if (projectError || formConfigError)
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

  const dataset = projectData?.datasets?.find((ds) => ds.id === datasetId);

  if (!dataset) {
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
      {/* Breadcrumb navigation */}
      <nav className="mb-6" aria-label="Breadcrumb">
        <ol className="flex items-center space-x-2 text-sm text-gray-500">
          <li>
            <Link
              href={`/projects/${projectNumber}`}
              className="hover:text-gray-700"
            >
              Project {projectNumber}
            </Link>
          </li>
          <li>/</li>
          <li>
            <Link
              href={`/projects/${projectNumber}/datasets`}
              className="hover:text-gray-700"
            >
              Datasets
            </Link>
          </li>
          <li>/</li>
          <li>
            <Link
              href={`/projects/${projectNumber}/datasets/${datasetId}`}
              className="hover:text-gray-700"
            >
              {dataset.name}
            </Link>
          </li>
          <li>/</li>
          <li className="text-gray-900 font-medium" aria-current="page">
            Run {appName}
          </li>
        </ol>
      </nav>

      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold">Run Application: {appName}</h1>
          <p className="text-gray-600 mt-1">Dataset: {dataset.name}</p>
          <p className="text-gray-600 mt-1">
            Descripton: QC tool from github.com/.... {"{app.description}"}
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
                {formConfig?.fields.map((field) => (
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
