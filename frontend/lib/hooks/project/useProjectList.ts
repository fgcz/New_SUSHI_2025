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
 * Hook to get the list of user projects.
 * User identity is determined from JWT token on the backend.
 */
export function useProjectList(): UseProjectListReturn {
  const { loading: authLoading, authStatus } = useAuth();

  const { data: userProjectsData, isLoading, error, refetch } = useQuery({
    queryKey: ['user-projects'],
    queryFn: () => projectApi.getUserProjects(),
    enabled: !authLoading && !!authStatus?.current_user,
    staleTime: 60_000,
  });

  const isEmpty = !isLoading && !error && (!userProjectsData || userProjectsData.projects.length === 0);

  return {
    userProjects: userProjectsData,
    isLoading: authLoading || isLoading,
    error,
    isEmpty,
    refetch
  };
}
