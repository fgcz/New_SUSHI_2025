import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, act, waitFor } from '@testing-library/react';
import { useJobSubmission } from './useJobSubmission';

const mockSubmitJob = vi.fn();

vi.mock('@/lib/api', () => ({
  jobApi: {
    submitJob: (...args: any[]) => mockSubmitJob(...args),
  },
}));

describe('useJobSubmission', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockSubmitJob.mockReset();
  });

  it('initializes with default state', () => {
    const { result } = renderHook(() => useJobSubmission());

    expect(result.current.isSubmitting).toBe(false);
    expect(result.current.error).toBeNull();
    expect(result.current.success).toBe(false);
  });

  it('sets isSubmitting to true during submission', async () => {
    mockSubmitJob.mockImplementation(() => new Promise((resolve) => setTimeout(resolve, 100)));

    const { result } = renderHook(() => useJobSubmission());

    act(() => {
      result.current.submitJob({
        project_number: 1001,
        dataset_id: 1,
        app_name: 'TestApp',
        next_dataset: { name: 'Output', comment: '' },
        parameters: {},
      });
    });

    expect(result.current.isSubmitting).toBe(true);
  });

  it('sets success to true on successful submission', async () => {
    mockSubmitJob.mockResolvedValue({ jobId: 123 });

    const { result } = renderHook(() => useJobSubmission());

    await act(async () => {
      await result.current.submitJob({
        project_number: 1001,
        dataset_id: 1,
        app_name: 'TestApp',
        next_dataset: { name: 'Output', comment: '' },
        parameters: {},
      });
    });

    expect(result.current.success).toBe(true);
    expect(result.current.error).toBeNull();
    expect(result.current.isSubmitting).toBe(false);
  });

  async function submitAndFailWith(thrown: unknown) {
    mockSubmitJob.mockRejectedValue(thrown);
    const { result } = renderHook(() => useJobSubmission());

    await act(async () => {
      await result.current.submitJob({
        project_number: 1001,
        dataset_id: 1,
        app_name: 'TestApp',
        next_dataset: { name: 'Output', comment: '' },
        parameters: {},
      });
    });

    return result;
  }

  it('reports what the server said, not a fixed sentence', async () => {
    const result = await submitAndFailWith(new Error('Network error'));

    expect(result.current.error).toBe('Network error');
    expect(result.current.success).toBe(false);
    expect(result.current.isSubmitting).toBe(false);
  });

  // What a user actually hit on the production node: submitting is refused there
  // by the read-only write policy. The old fixed text said "Please try again",
  // advice that can never succeed against a permanent refusal.
  it('passes a read-only refusal through verbatim', async () => {
    const refusal = new Error(
      "This SUSHI backend write policy is 'read_only'; POST /api/v1/jobs is not permitted.",
    );

    const result = await submitAndFailWith(refusal);

    expect(result.current.error).toContain('read_only');
    expect(result.current.error).not.toContain('try again');
  });

  it('still says something when the thrown value carries no message', async () => {
    const result = await submitAndFailWith(new Error(''));

    expect(result.current.error).toBe('Failed to submit job.');
  });

  it('resets error before new submission', async () => {
    mockSubmitJob.mockRejectedValueOnce(new Error('First error'));
    mockSubmitJob.mockResolvedValueOnce({ jobId: 123 });

    const { result } = renderHook(() => useJobSubmission());

    // First submission fails
    await act(async () => {
      await result.current.submitJob({
        project_number: 1001,
        dataset_id: 1,
        app_name: 'TestApp',
        next_dataset: { name: 'Output', comment: '' },
        parameters: {},
      });
    });

    expect(result.current.error).not.toBeNull();

    // Second submission should clear error
    await act(async () => {
      await result.current.submitJob({
        project_number: 1001,
        dataset_id: 1,
        app_name: 'TestApp',
        next_dataset: { name: 'Output', comment: '' },
        parameters: {},
      });
    });

    expect(result.current.error).toBeNull();
    expect(result.current.success).toBe(true);
  });

  it('resetState clears error and success', async () => {
    mockSubmitJob.mockResolvedValue({ jobId: 123 });

    const { result } = renderHook(() => useJobSubmission());

    await act(async () => {
      await result.current.submitJob({
        project_number: 1001,
        dataset_id: 1,
        app_name: 'TestApp',
        next_dataset: { name: 'Output', comment: '' },
        parameters: {},
      });
    });

    expect(result.current.success).toBe(true);

    act(() => {
      result.current.resetState();
    });

    expect(result.current.success).toBe(false);
    expect(result.current.error).toBeNull();
  });

  it('passes job data to API', async () => {
    mockSubmitJob.mockResolvedValue({ jobId: 123 });

    const { result } = renderHook(() => useJobSubmission());
    const jobData = {
      project_number: 1001,
      dataset_id: 1,
      app_name: 'TestApp',
      next_dataset: { name: 'Output', comment: 'Test comment' },
      parameters: { cores: 4, ram: 16 },
    };

    await act(async () => {
      await result.current.submitJob(jobData);
    });

    expect(mockSubmitJob).toHaveBeenCalledWith(jobData);
  });
});
