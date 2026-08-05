'use client';

import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { authApi, httpClient } from '@/lib/api';
import { AuthState } from '@/lib/types';

interface AuthContextType {
  authStatus: AuthState | null;
  loading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [authStatus, setAuthStatus] = useState<AuthState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();
  const pathname = usePathname();

  const handleUnauthorized = useCallback(() => {
    // Clear local state and redirect to login
    authApi.logout();
    setAuthStatus(null);
    router.push('/login');
  }, [router]);

  const fetchAuthStatus = async () => {
    try {
      setLoading(true);
      setError(null);

      // Get authentication options from backend
      const options = await authApi.getAuthenticationStatus();

      // Try to get current user from /auth/me
      // Backend returns dev_user when SKIP_AUTH=true, even without token
      try {
        const userInfo = await authApi.verifyToken();
        setAuthStatus({
          ...options,
          current_user: userInfo.login,
        });
      } catch {
        // No valid session
        if (options.authentication_skipped) {
          // This shouldn't happen - backend should return dev_user
          console.error('SKIP_AUTH is true but /auth/me failed');
        }
        setAuthStatus({
          ...options,
          current_user: null,
        });

        // Redirect to login if auth is required
        if (!options.authentication_skipped && pathname !== '/login') {
          router.push('/login');
        }
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch authentication status');
      console.error('Error fetching auth status:', err);

      if (pathname !== '/login') {
        router.push('/login');
      }
    } finally {
      setLoading(false);
    }
  };

  const logout = async () => {
    await authApi.logout();
    setAuthStatus(null);
    router.push('/login');
  };

  // Register 401 handler and fetch auth status once on mount
  useEffect(() => {
    httpClient.setUnauthorizedHandler(handleUnauthorized);
    fetchAuthStatus();
  }, []);

  const value: AuthContextType = {
    authStatus,
    loading,
    error,
    refetch: fetchAuthStatus,
    logout,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
} 
