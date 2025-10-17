import { useMemo } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';

interface UsePaginationReturn {
  page: number;
  per: number;
  goToPage: (page: number) => void;
  changePerPage: (per: number) => void;
}

/**
 * Hook to manage pagination state in URL parameters
 * 
 * @param defaultPerPage - Default items per page (default: 50)
 * @returns Object containing pagination state and handlers
 */
export function usePagination(defaultPerPage: number = 50): UsePaginationReturn {
  const router = useRouter();
  const searchParams = useSearchParams();

  // URL-driven pagination parameters
  const page = useMemo(() => Number(searchParams.get('page') || 1), [searchParams]);
  const per = useMemo(() => Number(searchParams.get('per') || defaultPerPage), [searchParams, defaultPerPage]);

  const goToPage = (nextPage: number) => {
    const sp = new URLSearchParams(searchParams);
    sp.set('page', String(nextPage));
    router.push(`?${sp.toString()}`);
  };

  const changePerPage = (nextPer: number) => {
    const sp = new URLSearchParams(searchParams);
    sp.set('per', String(nextPer));
    sp.set('page', '1'); // Reset to page 1 when changing per-page count
    router.push(`?${sp.toString()}`);
  };

  return {
    page,
    per,
    goToPage,
    changePerPage
  };
}