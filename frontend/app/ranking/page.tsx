'use client';

import { useQuery } from '@tanstack/react-query';
import { projectApi } from '@/lib/api';

export default function RankingPage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['rankings'],
    queryFn: () => projectApi.getRankings(),
    staleTime: 60_000,
  });

  if (isLoading) {
    return (
      <div className="container mx-auto px-6 py-8">
        <div className="animate-pulse">
          <div className="h-8 bg-gray-200 rounded w-48 mb-6"></div>
          <div className="bg-white border rounded-lg">
            {[...Array(10)].map((_, i) => (
              <div key={i} className="flex items-center px-6 py-4 border-b last:border-b-0">
                <div className="h-4 bg-gray-200 rounded w-8 mr-6"></div>
                <div className="h-4 bg-gray-200 rounded w-32 mr-auto"></div>
                <div className="h-4 bg-gray-200 rounded w-16 mr-6"></div>
                <div className="h-4 bg-gray-200 rounded w-20"></div>
              </div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="container mx-auto px-6 py-8">
        <div className="text-center py-12">
          <div className="text-red-600 text-lg font-medium mb-2">Failed to load rankings</div>
          <p className="text-gray-500">There was an error loading the rankings data.</p>
        </div>
      </div>
    );
  }

  const rankings = data?.rankings ?? [];

  return (
    <div className="container mx-auto px-6 py-8">
      <div className="mb-6">
        <h1 className="text-2xl text-gray-900">User Rankings</h1>
        <p className="text-gray-500 text-sm mt-1">Job submissions leaderboard</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden shadow-sm">
        <table className="min-w-full">
          <thead style={{ backgroundColor: '#6CD3D1' }}>
            <tr>
              <th className="px-6 py-3 text-left text-xs text-gray-700 uppercase tracking-wider w-20">
                Rank
              </th>
              <th className="px-6 py-3 text-left text-xs text-gray-700 uppercase tracking-wider">
                Username
              </th>
              <th className="px-6 py-3 text-right text-xs text-gray-700 uppercase tracking-wider">
                This Month
              </th>
              <th className="px-6 py-3 text-right text-xs text-gray-700 uppercase tracking-wider">
                Total Submissions
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {rankings.map((user, index) => {
              const rank = index + 1;
              return (
                <tr key={user.username} className="hover:bg-gray-50">
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm text-gray-700">{rank}</span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm text-gray-700">{user.username}</span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-right">
                    <span className="text-sm text-gray-700">{user.jobs_this_month.toLocaleString()}</span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-right">
                    <span className="text-sm text-gray-700">{user.total_submissions.toLocaleString()}</span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="mt-4 text-xs text-gray-400 text-center">
        Rankings are updated daily
      </div>
    </div>
  );
}
