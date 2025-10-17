import { useQuery } from '@tanstack/react-query';
import { projectApi } from '@/lib/api';
import { ProjectDataset } from '@/lib/types';

interface UseDatasetBaseReturn {
  dataset: ProjectDataset | undefined;
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
  projectNumber: number, 
  datasetId: number
): UseDatasetBaseReturn {
  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['datasets', projectNumber],
    queryFn: () => projectApi.getProjectDatasets(projectNumber),
    staleTime: 60_000,
  });

  // Business logic: Find the specific dataset by ID
  const dataset = data?.datasets?.find(ds => ds.id === datasetId);
  
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
