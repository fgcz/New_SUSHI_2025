import { useQuery } from '@tanstack/react-query';
import { datasetApi } from '@/lib/api';
import { DatasetTreeNode } from '@/lib/types';

interface UseDatasetTreeReturn {
  datasetTree: DatasetTreeNode[] | undefined;
  isLoading: boolean;
  error: Error | null;
  isEmpty: boolean;
  refetch: () => void;
}

/**
 * Hook to get the tree of datasets in the parent-child relationship for a specific dataset 
 * 
 * @param datasetId - The specific dataset ID to retrieve
 * @returns Object containing dataset tree, loading state, error state, and utility functions
 */
export function useDatasetTree(
  datasetId: number
): UseDatasetTreeReturn {
  const { data: datasetTree, isLoading, error, refetch } = useQuery({
    queryKey: ['datasetTree', datasetId],
    queryFn: () => datasetApi.getDatasetTree(datasetId),
    staleTime: 60_000,
  });

  // Computed state: Determine if tree is empty
  const isEmpty = !isLoading && !error && (!datasetTree || datasetTree.length === 0);

  return {
    datasetTree,
    isLoading,
    error,
    isEmpty,
    refetch
  };
}
