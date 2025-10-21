import { useQuery } from '@tanstack/react-query';
import { projectApi } from '@/lib/api';
import { UserProjectsResponse } from '@/lib/types';
import { useAuth } from '@/providers/AuthContext';

interface UseProjectListReturn {
  userProjects: UserProjectsResponse | undefined;
  isLoading: boolean;
  error: Error | null;
  isEmpty: boolean;
  refetch: () => void;
}

/**
 * Hook to get the list of user projects
 * 
 * @param 
 * @returns Object containing project list, loading state, error state, and utility functions
 */
export function useProjectList(): UseProjectListReturn {
  const { loading: authLoading } = useAuth();
  
  const { data: userProjectsData, isLoading, error, refetch } = useQuery({
    queryKey: ['user-projects'],
    queryFn: () => projectApi.getUserProjects(),
    enabled: !authLoading,
    staleTime: 60_000,
  });

  // Computed state: Determine if projects list is empty
  const isEmpty = !isLoading && !error && (!userProjectsData || userProjectsData.projects.length === 0);

  return {
    userProjects: userProjectsData,
    isLoading: authLoading || isLoading,
    error,
    isEmpty,
    refetch
  };

  
}
