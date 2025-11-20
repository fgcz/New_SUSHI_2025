import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { projectApi } from '@/lib/api';
import { ProjectDatasetsResponse } from '@/lib/types';

interface UseProjectDatasetsParams {
  projectNumber: number;
  datasetName?: string;
  user?: string;
  page?: number;
  per?: number;
}

interface UseProjectDatasetsReturn {
  data: ProjectDatasetsResponse | undefined;
  datasets: ProjectDatasetsResponse['datasets'];
  total: number;
  currentPage: number;
  perPage: number;
  totalPages: number;
  isLoading: boolean;
  error: Error | null;
  isEmpty: boolean;
}

/**
 * Hook to fetch paginated datasets for a project with search functionality
 * 
 * @param params - Query parameters including projectNumber, search query, page, and per-page count
 * @returns Object containing datasets data, pagination info, loading state, and error state
 */
export function useProjectDatasets({ 
  projectNumber, 
  datasetName = '', 
  user = '',
  page = 1, 
  per = 50 
}: UseProjectDatasetsParams): UseProjectDatasetsReturn {
  const { data, isLoading, error } = useQuery({
    queryKey: ['datasets', projectNumber, { datasetName, user, page, per }],
    queryFn: () => projectApi.getProjectDatasets(projectNumber, { datasetName, user, page, per }),
    placeholderData: keepPreviousData,
    staleTime: 60_000,
  });

  const datasets = data?.datasets ?? [];
  const total = data?.total_count ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / per));
  const isEmpty = !isLoading && !error && datasets.length === 0;

  return {
    data,
    datasets,
    total,
    currentPage: page,
    perPage: per,
    totalPages,
    isLoading,
    error,
    isEmpty
  };
}
