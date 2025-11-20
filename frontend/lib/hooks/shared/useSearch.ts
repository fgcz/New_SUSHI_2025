import { useEffect, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';

interface UseSearchReturn {
  searchQuery: string;
  localQuery: string;
  setLocalQuery: (query: string) => void;
  onSubmit: (e: React.FormEvent) => void;
}

/**
 * Hook to manage search input with debounced URL updates
 * 
 * @param paramName - URL parameter name (default: 'q')
 * @param debounceMs - Debounce delay in milliseconds (default: 300)
 * @returns Object containing search state and handlers
 */
export function useSearch(paramName: string = 'q', debounceMs: number = 300): UseSearchReturn {
  const router = useRouter();
  const searchParams = useSearchParams();
  
  // URL-driven search parameter
  const searchQuery = useMemo(() => searchParams.get(paramName) || '', [searchParams, paramName]);
  
  // Local input state for immediate UI updates
  const [localQuery, setLocalQuery] = useState(searchQuery);
  
  // Sync local state when URL changes (e.g., browser back/forward)
  useEffect(() => {
    setLocalQuery(searchQuery);
  }, [searchQuery]);

  // Debounced URL update
  useEffect(() => {
    const timeoutId = setTimeout(() => {
      // Only update URL if the search term actually changed
      if (localQuery !== searchQuery) {
        const sp = new URLSearchParams(searchParams.toString());
        if (localQuery.trim()) {
          sp.set(paramName, localQuery.trim());
        } else {
          sp.delete(paramName);
        }
        sp.set('page', '1'); // Reset to page 1 on new search
        
        router.push(`?${sp.toString()}`);
      }
    }, debounceMs);

    return () => clearTimeout(timeoutId);
  }, [localQuery, searchQuery, searchParams, router, debounceMs, paramName]);

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    // Search is handled by debounce, but keep form for accessibility
  };

  return {
    searchQuery,
    localQuery,
    setLocalQuery,
    onSubmit
  };
}