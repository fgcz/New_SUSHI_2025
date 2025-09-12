'use client';

import Link from 'next/link';
import { useAuth } from '@/contexts/AuthContext';
import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/lib/api';

export default function ProjectsPage() {
  const { loading: authLoading } = useAuth();

  const { data, isLoading, error } = useQuery({
    queryKey: ['user-projects'],
    queryFn: () => apiClient.getUserProjects(),
    enabled: !authLoading,
    staleTime: 5 * 60 * 1000,
  });

  if (authLoading || isLoading) return <div className="p-6">Loading projects...</div>;
  if (error) return <div className="p-6 text-red-600">Failed to load projects</div>;

  const projects = data?.projects ?? [];

  return (
    <div className="container mx-auto px-6 py-8">
      <h1 className="text-2xl font-bold mb-6">Select Project</h1>
      {projects.length === 0 ? (
        <div className="text-gray-600">No accessible projects found.</div>
      ) : (
        <div className="grid gap-4">
          {projects.map((p) => (
            <Link key={p.number} href={`/projects/${p.number}`} className="block p-4 border rounded hover:bg-gray-50">
              <span className="font-semibold">Project {p.number}</span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}



