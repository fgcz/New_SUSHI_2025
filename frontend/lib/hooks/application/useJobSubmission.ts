import { useState, useCallback } from "react";
import { jobApi } from "@/lib/api";
import { JobSubmissionRequest } from "@/lib/types";

export interface UseJobSubmissionReturn {
  submitJob: (jobData: JobSubmissionRequest) => Promise<void>;
  isSubmitting: boolean;
  error: string | null;
  success: boolean;
  resetState: () => void;
}

export function useJobSubmission(): UseJobSubmissionReturn {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const submitJob = useCallback(async (jobData: JobSubmissionRequest) => {
    setIsSubmitting(true);
    setError(null);
    setSuccess(false);

    // Log form data to console
    console.log("Submitting job with data:", jobData);

    try {
      const response = await jobApi.submitJob(jobData);
      console.log("Job submission response:", response);
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
  }, []);

  return {
    submitJob,
    isSubmitting,
    error,
    success,
    resetState,
  };
}