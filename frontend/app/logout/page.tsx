'use client';

import React, { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { apiClient } from '@/lib/api';

export default function LogoutPage() {
  const router = useRouter();

  useEffect(() => {
    const performLogout = async () => {
      try {
        // Call logout API to invalidate token on server side (if needed)
        await apiClient.logout();
        
        // Clear JWT token from localStorage
        if (typeof window !== 'undefined') {
          localStorage.removeItem('jwt_token');
        }
        
        // Redirect to login page
        router.push('/login');
      } catch (error) {
        console.error('Logout error:', error);
        // Even if API call fails, clear local token and redirect
        if (typeof window !== 'undefined') {
          localStorage.removeItem('jwt_token');
        }
        router.push('/login');
      }
    };

    performLogout();
  }, [router]);

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="text-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto"></div>
        <p className="mt-2 text-gray-600">Logging out...</p>
      </div>
    </div>
  );
} 