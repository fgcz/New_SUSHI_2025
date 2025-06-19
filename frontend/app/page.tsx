'use client';

import { useEffect, useState } from 'react';
import { getApiBaseUrl } from '../config/api';

export default function Home() {
  const [message, setMessage] = useState<string>('');
  const [error, setError] = useState<string>('');
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [retryCount, setRetryCount] = useState<number>(0);
  const [currentHost, setCurrentHost] = useState<string>('');

  const API_BASE_URL = getApiBaseUrl();

  // Set current host after component mounts (client-side only)
  useEffect(() => {
    setCurrentHost(window.location.host);
  }, []);

  const fetchData = async () => {
    try {
      setIsLoading(true);
      setError('');
      console.log('Fetching data from API...');
      console.log('API Base URL:', API_BASE_URL);
      
      const response = await fetch(`${API_BASE_URL}/api/v1/hello`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
        mode: 'cors',
      });
      
      console.log('Response status:', response.status);
      console.log('Response headers:', response.headers);
      
      if (!response.ok) {
        throw new Error(`API request failed with status: ${response.status} - ${response.statusText}`);
      }
      
      const data = await response.json();
      console.log('Response data:', data);
      setMessage(data.message);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch data from API';
      setError(errorMessage);
      console.error('Error details:', err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [retryCount]);

  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24 bg-gray-50">
      <div className="z-10 max-w-5xl w-full items-center justify-between font-mono text-sm">
        <h1 className="text-4xl font-bold mb-8 text-center text-gray-800">SUSHI System</h1>
        
        <div className="bg-white p-8 rounded-lg shadow-md">
          <div className="mb-4 text-sm text-gray-600">
            <p>Frontend: {currentHost || 'Loading...'}</p>
            <p>Backend: {API_BASE_URL}</p>
          </div>
          
          {error ? (
            <div className="text-red-500 mb-4">
              <p className="font-bold">Error occurred:</p>
              <p className="text-sm">{error}</p>
              <button
                onClick={() => setRetryCount(prev => prev + 1)}
                className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 transition-colors"
              >
                Retry
              </button>
            </div>
          ) : (
            <div className="text-xl">
              {isLoading ? (
                <div className="flex items-center justify-center">
                  <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
                  <span className="ml-2">Loading...</span>
                </div>
              ) : (
                <p className="text-gray-700">Message from API: {message}</p>
              )}
            </div>
          )}
        </div>
      </div>
    </main>
  );
}
