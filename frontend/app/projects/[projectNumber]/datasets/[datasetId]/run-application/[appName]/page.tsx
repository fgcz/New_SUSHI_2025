"use client";

import { useEffect, useCallback, useRef } from "react";
import Link from "next/link";
import { useParams, useRouter, useSearchParams, usePathname } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { FormFieldComponent } from "@/lib/utils/form-renderer";
import Breadcrumbs from "@/lib/ui/Breadcrumbs";
import {
  useDatasetBase,
  useApplicationFormSchema,
  useApplicationForm,
} from "@/lib/hooks";
import { datasetApi } from "@/lib/api";
import RunApplicationPageSkeleton from "./RunApplicationPageSkeleton";
import FormStepper from "./FormStepper";
import StepNavigation from "./StepNavigation";

export default function RunApplicationPage() {
  // ============================================
  // URL PARAMS
  // ============================================
  const params = useParams<{
    projectNumber: string;
    datasetId: string;
    appName: string;
  }>();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);
  const appName = params.appName;
  const isResubmit = searchParams.get("resubmit") === "true";

  const paramsRef = useRef<HTMLDivElement>(null);

  // ============================================
  // DATA FETCHING
  // ============================================
  const {
    dataset,
    isLoading: isDatasetLoading,
    error: datasetError,
    notFound: datasetNotFound,
  } = useDatasetBase(datasetId);

  const {
    data: formConfigData,
    isLoading: isFormConfigLoading,
    error: formConfigError,
  } = useApplicationFormSchema(appName);

  const { data: resubmitData, isLoading: isResubmitLoading } = useQuery({
    queryKey: ["resubmit-data", datasetId],
    queryFn: () => datasetApi.getResubmitData(datasetId),
    enabled: isResubmit,
    staleTime: Infinity,
  });

  const formConfig = formConfigData?.application;

  // ============================================
  // FORM HOOK
  // ============================================
  const {
    nextDatasetData,
    formValues,
    paramGroups,
    handleInputChange,
    handleFieldChange,
    handleFieldBlur,
    handleKeyDown,
  } = useApplicationForm({
    appName,
    datasetId,
    datasetName: dataset?.name,
    paramGroups: formConfig?.param_groups,
    resubmitParams: resubmitData?.parameters,
    isResubmit,
  });

  // ============================================
  // STEP NAVIGATION (1-based: step=1, step=2, etc.)
  // ============================================
  const currentStepParam = searchParams.get("step");
  const currentStepNumber = currentStepParam !== null
    ? Math.max(1, Math.min(parseInt(currentStepParam, 10), paramGroups.length))
    : 1;
  const currentStepIndex = currentStepNumber - 1; // Convert to 0-based for array access
  const currentStep = paramGroups[currentStepIndex];
  const isFirstStep = currentStepNumber === 1;
  const isLastStep = currentStepNumber === paramGroups.length;

  // Redirect to step=1 if no step param and we have groups
  useEffect(() => {
    if (paramGroups.length > 0 && currentStepParam === null) {
      const newParams = new URLSearchParams(searchParams);
      newParams.set("step", "1");
      router.replace(`${pathname}?${newParams.toString()}`);
    }
  }, [paramGroups.length, currentStepParam, searchParams, pathname, router]);

  const goToStep = useCallback((stepIndex: number) => {
    const newParams = new URLSearchParams(searchParams);
    // stepIndex is 0-based from FormStepper, convert to 1-based for URL
    newParams.set("step", (stepIndex + 1).toString());
    router.push(`${pathname}?${newParams.toString()}`, { scroll: false });
  }, [searchParams, pathname, router]);

  // Scroll to params section when step changes via stepper click
  const prevStepRef = useRef(currentStepNumber);
  useEffect(() => {
    if (prevStepRef.current !== currentStepNumber) {
      paramsRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
      prevStepRef.current = currentStepNumber;
    }
  }, [currentStepNumber]);

  const goNext = useCallback(() => {
    if (currentStepNumber < paramGroups.length) {
      const newParams = new URLSearchParams(searchParams);
      newParams.set("step", (currentStepNumber + 1).toString());
      router.push(`${pathname}?${newParams.toString()}`);
    }
  }, [currentStepNumber, paramGroups.length, searchParams, pathname, router]);

  const goBack = useCallback(() => {
    if (currentStepNumber > 1) {
      const newParams = new URLSearchParams(searchParams);
      newParams.set("step", (currentStepNumber - 1).toString());
      router.push(`${pathname}?${newParams.toString()}`);
    }
  }, [currentStepNumber, searchParams, pathname, router]);

  // ============================================
  // SUBMIT HANDLER
  // ============================================
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!dataset) return;

    const jobData = {
      projectNumber,
      datasetId,
      appName,
      nextDataset: {
        name: nextDatasetData.datasetName,
        comment: nextDatasetData.datasetComment || undefined,
      },
      parameters: formValues,
    };

    try {
      sessionStorage.setItem("sushi_job_submission_data", JSON.stringify(jobData));
      router.push(
        `/projects/${projectNumber}/datasets/${datasetId}/run-application/${appName}/confirm`
      );
    } catch (error) {
      console.error("Failed to store job data:", error);
      alert("Failed to save job data. Please try again.");
    }
  };

  // ============================================
  // EARLY RETURNS
  // ============================================
  if (isDatasetLoading || isFormConfigLoading || (isResubmit && isResubmitLoading)) {
    return <RunApplicationPageSkeleton />;
  }

  if (datasetError || formConfigError) {
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
            className="text-brand-600 hover:underline"
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
        <h1 className="text-2xl font-bold mb-4 text-red-600">Dataset Not Found</h1>
        <p className="text-gray-700 mb-6">
          Dataset {datasetId} was not found in project {projectNumber}.
        </p>
        <Link
          href={`/projects/${projectNumber}/datasets`}
          className="text-brand-600 hover:underline"
        >
          ← Back to Datasets
        </Link>
      </div>
    );
  }

  // Check if app is available (currently just logs)
  const isAppAvailable = dataset.applications?.some((category: { apps: { class_name: string }[] }) =>
    category.apps.some((app: { class_name: string }) => app.class_name === appName)
  );
  if (!isAppAvailable) {
    console.log("This Application cannot run on this dataset");
  }

  // ============================================
  // RENDER
  // ============================================
  return (
    <div className="container mx-auto px-6 py-8">
      <Breadcrumbs
        items={[
          { label: `Project ${projectNumber}`, href: `/projects/${projectNumber}` },
          { label: "Datasets", href: `/projects/${projectNumber}/datasets` },
          { label: dataset.name, href: `/projects/${projectNumber}/datasets/${datasetId}` },
          { label: `Run ${appName}`, active: true },
        ]}
      />

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

      {/* NextDataset Section - above steps since it doesn't change */}
      <div className="bg-white border rounded-lg overflow-hidden mb-6">
        <div className="px-6 py-4">
          <h3 className="text-lg font-semibold mb-4">NextDataset</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label
                htmlFor="datasetName"
                className="block text-sm font-medium text-gray-700 mb-1"
              >
                Name
              </label>
              <input
                type="text"
                id="datasetName"
                name="datasetName"
                value={nextDatasetData.datasetName}
                onChange={handleInputChange}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
                placeholder={`${appName}_${dataset.name}_${new Date().toISOString().slice(0, 10)}`}
              />
            </div>
            <div>
              <label
                htmlFor="datasetComment"
                className="block text-sm font-medium text-gray-700 mb-1"
              >
                Comment
              </label>
              <input
                type="text"
                id="datasetComment"
                name="datasetComment"
                value={nextDatasetData.datasetComment}
                onChange={handleInputChange}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
                placeholder="Optional comment..."
              />
            </div>
          </div>
        </div>
      </div>

      {/* Step Progress Indicator */}
      {paramGroups.length > 0 && (
        <FormStepper
          steps={paramGroups}
          currentStepIndex={currentStepIndex}
          onStepClick={goToStep}
        />
      )}

      <div className="space-y-6">
        {/* Current Step Parameters */}
        {currentStep && (
          <div ref={paramsRef} className="bg-white border rounded-lg overflow-hidden">
            <div className="px-6 py-4">
              <div className="mb-4">
                <h3 className="text-lg font-semibold">{currentStep.title}</h3>
                {currentStep.description && (
                  <p className="text-sm text-gray-500 mt-1">{currentStep.description}</p>
                )}
              </div>
              <form onSubmit={handleSubmit}>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-4">
                  {currentStep.fields.map((field) => (
                    <FormFieldComponent
                      key={field.name}
                      field={field}
                      value={formValues[field.name]}
                      onChange={handleFieldChange}
                      onBlur={handleFieldBlur}
                      onKeyDown={handleKeyDown}
                    />
                  ))}
                </div>
                <StepNavigation
                  onBack={goBack}
                  onNext={goNext}
                  isFirstStep={isFirstStep}
                  isLastStep={isLastStep}
                />
              </form>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
