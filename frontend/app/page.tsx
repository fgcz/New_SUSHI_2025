'use client';

import { useEffect, useState } from 'react';

export default function Home() {
  const [message, setMessage] = useState<string>('');
  const [error, setError] = useState<string>('');
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [retryCount, setRetryCount] = useState<number>(0);

  const fetchData = async () => {
    try {
      setIsLoading(true);
      setError('');
      const response = await fetch('http://fgcz-h-037.fgcz-net.unizh.ch:4000/api/v1/hello');
      if (!response.ok) {
        throw new Error(`API request failed with status: ${response.status}`);
      }
      const data = await response.json();
      setMessage(data.message);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'APIからのデータ取得に失敗しました');
      console.error('Error:', err);
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
          {error ? (
            <div className="text-red-500 mb-4">
              <p className="font-bold">エラーが発生しました：</p>
              <p>{error}</p>
              <button
                onClick={() => setRetryCount(prev => prev + 1)}
                className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 transition-colors"
              >
                再試行
              </button>
            </div>
          ) : (
            <div className="text-xl">
              {isLoading ? (
                <div className="flex items-center justify-center">
                  <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
                  <span className="ml-2">読み込み中...</span>
                </div>
              ) : (
                <p className="text-gray-700">APIからのメッセージ: {message}</p>
              )}
            </div>
          )}
        </div>
      </div>
    </main>
  );
}
