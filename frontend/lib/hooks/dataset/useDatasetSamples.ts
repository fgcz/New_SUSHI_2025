import { useQuery } from '@tanstack/react-query';
import { datasetApi } from '@/lib/api';
import { DatasetSample } from '@/lib/types';

interface UseDatasetSamplesReturn {
  samples: DatasetSample[] | undefined;
  isLoading: boolean;
  error: Error | null;
  isEmpty: boolean;
  refetch: () => void;
}

/**
 * Hook to get the list of samples for a specific dataset
 * 
 * @param datasetId - The specific dataset ID to retrieve samples for
 * @returns Object containing samples data, loading state, error state, and utility functions
 */
export function useDatasetSamples(
  datasetId: number
): UseDatasetSamplesReturn {
  const { data: samples, isLoading, error, refetch } = useQuery({
    queryKey: ['datasetSamples', datasetId],
    queryFn: () => datasetApi.getDatasetSamples(datasetId),
    staleTime: 60_000,
  });

  // Computed state: Determine if samples list is empty
  const isEmpty = !isLoading && !error && (!samples || samples.length === 0);

  return {
    samples,
    isLoading,
    error,
    isEmpty,
    refetch
  };
}