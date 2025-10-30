import { useQuery } from '@tanstack/react-query';
import { datasetApi } from '@/lib/api';
import { DatasetResponse } from '@/lib/types';

interface UseDatasetBaseReturn {
  dataset: DatasetResponse | undefined;
  isLoading: boolean;
  error: Error | null;
  notFound: boolean;
  refetch: () => void;
}

/**
 * Hook to get basic dataset information for a specific dataset within a project
 * 
 * @param projectNumber - The project number containing the dataset
 * @param datasetId - The specific dataset ID to retrieve
 * @returns Object containing dataset data, loading state, error state, and utility functions
 */
export function useDatasetBase(
  datasetId: number
): UseDatasetBaseReturn {
  const { data: dataset, isLoading, error, refetch } = useQuery({
    queryKey: ['datasets', datasetId],
    queryFn: () => datasetApi.getDataset(datasetId),
    staleTime: 60_000,
  });
  
  // Computed state: Determine if dataset was not found
  const notFound = !isLoading && !error && !dataset;

  return {
    dataset,
    isLoading,
    error,
    notFound,
    refetch
  };
}
