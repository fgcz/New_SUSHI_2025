import { useEffect, useState } from 'react';

const STORAGE_KEY = 'lastProjectNumber';

/**
 * Returns the effective project number: uses the provided value if present,
 * otherwise falls back to the last project number saved in localStorage.
 * Saves to localStorage whenever a valid number is provided.
 */
export function useLastProjectNumber(projectNumber: number | null | undefined): number | null {
  const [stored, setStored] = useState<number | null>(() => {
    if (typeof window === 'undefined') return null;
    return Number(localStorage.getItem(STORAGE_KEY)) || null;
  });

  useEffect(() => {
    if (projectNumber) {
      localStorage.setItem(STORAGE_KEY, projectNumber.toString());
      setStored(projectNumber);
    }
  }, [projectNumber]);

  return projectNumber ?? stored;
}
