import { useQuery } from '@tanstack/react-query';
import { datasetApi } from '@/lib/api';
import { DatasetRunnableApp } from '@/lib/types';

interface UseDatasetAppsReturn {
  apps: DatasetRunnableApp[] | undefined;
  isLoading: boolean;
  error: Error | null;
  isEmpty: boolean;
  refetch: () => void;
}

/**
 * Hook to get the list of runnable apps for a specific dataset
 * 
 * @param datasetId - The specific dataset ID to retrieve
 * @returns Object containing dataset data, loading state, error state, and utility functions
 */
export function useDatasetApps(
  datasetId: number
): UseDatasetAppsReturn {
  const { data: apps, isLoading, error, refetch } = useQuery({
    queryKey: ['runnableApps', datasetId],
    queryFn: () => datasetApi.getRunnableApps(datasetId),
    staleTime: 60_000,
  });

  // Computed state: Determine if apps list is empty
  const isEmpty = !isLoading && !error && (!apps || apps.length === 0);

  return {
    apps,
    isLoading,
    error,
    isEmpty,
    refetch
  };
}
