'use client';

import React, { createContext, useContext, useEffect, useState } from 'react';
import { apiClient, AuthenticationStatus } from '@/lib/api';

interface AuthContextType {
  authStatus: AuthenticationStatus | null;
  loading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [authStatus, setAuthStatus] = useState<AuthenticationStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchAuthStatus = async () => {
    try {
      setLoading(true);
      setError(null);
      const status = await apiClient.getAuthenticationStatus();
      setAuthStatus(status);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch authentication status');
      console.error('Error fetching auth status:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAuthStatus();
  }, []);

  const value: AuthContextType = {
    authStatus,
    loading,
    error,
    refetch: fetchAuthStatus,
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