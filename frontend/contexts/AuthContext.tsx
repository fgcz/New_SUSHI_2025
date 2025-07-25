'use client';

import React, { createContext, useContext, useEffect, useState } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { apiClient, AuthenticationStatus } from '@/lib/api';

interface AuthContextType {
  authStatus: AuthenticationStatus | null;
  loading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [authStatus, setAuthStatus] = useState<AuthenticationStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();
  const pathname = usePathname();

  const fetchAuthStatus = async () => {
    try {
      setLoading(true);
      setError(null);
      
      // Get authentication options from backend
      const status = await apiClient.getAuthenticationStatus();
      
      // If authentication is skipped, don't check JWT token
      if (status.authentication_skipped) {
        setAuthStatus(status);
        setLoading(false);
        return;
      }
      
      // If JWT token exists, verify it and get user info
      if (apiClient['token']) {
        try {
          const verifyResult = await apiClient.verifyToken();
          if (verifyResult.valid && verifyResult.user) {
            status.current_user = verifyResult.user.login;
          } else {
            // Token is invalid, clear it
            apiClient.logout();
          }
        } catch (verifyError) {
          // Token is invalid, clear it
          apiClient.logout();
        }
      }
      
      setAuthStatus(status);
      
      // Redirect to login page if authentication is required and not on login page
      if (!status.authentication_skipped && !status.current_user && pathname !== '/login') {
        router.push('/login');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch authentication status');
      console.error('Error fetching auth status:', err);
      
      // On error, redirect to login if not already there
      if (pathname !== '/login') {
        router.push('/login');
      }
    } finally {
      setLoading(false);
    }
  };

  const logout = () => {
    // Clear JWT token
    apiClient.logout();
    
    // Clear authentication status
    setAuthStatus(null);
    
    // Redirect to login page
    router.push('/login');
  };

  useEffect(() => {
    fetchAuthStatus();
  }, [pathname]);

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