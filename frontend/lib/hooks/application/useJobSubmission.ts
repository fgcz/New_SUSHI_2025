import { useState, useCallback } from "react";
import { jobApi } from "@/lib/api";
import { JobSubmissionRequest, JobSubmissionResponse } from "@/lib/types";

export interface UseJobSubmissionReturn {
  submitJob: (jobData: JobSubmissionRequest) => Promise<void>;
  isSubmitting: boolean;
  error: string | null;
  success: boolean;
  submissionResult: JobSubmissionResponse | null;
  resetState: () => void;
}

export function useJobSubmission(): UseJobSubmissionReturn {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [submissionResult, setSubmissionResult] = useState<JobSubmissionResponse | null>(null);

  const submitJob = useCallback(async (jobData: JobSubmissionRequest) => {
    setIsSubmitting(true);
    setError(null);
    setSuccess(false);
    setSubmissionResult(null);

    try {
      const response = await jobApi.submitJob(jobData);
      setSubmissionResult(response);
      setSuccess(true);
    } catch (error) {
      console.error("Job submission failed:", error);
      setError("Failed to submit job. Please try again.");
    } finally {
      setIsSubmitting(false);
    }
  }, []);

  const resetState = useCallback(() => {
    setError(null);
    setSuccess(false);
    setSubmissionResult(null);
  }, []);

  return {
    submitJob,
    isSubmitting,
    error,
    success,
    submissionResult,
    resetState,
  };
}
