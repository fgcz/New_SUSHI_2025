'use client';

import Link from 'next/link';
import { useProjectList } from '@/lib/hooks';

export default function ProjectsPage() {
  const { userProjects, isLoading, error, isEmpty } = useProjectList();

  if (isLoading) return <div className="p-6">Loading projects...</div>;
  if (error) return <div className="p-6 text-red-600">Failed to load projects</div>;

  return (
    <div className="container mx-auto px-6 py-8">
      <h1 className="text-2xl font-bold mb-6">Select Project</h1>
      {isEmpty ? (
        <div className="text-gray-600">No accessible projects found.</div>
      ) : (
        <div className="grid gap-4">
          {userProjects?.projects.map((p) => (
            <Link key={p.number} href={`/projects/${p.number}`} className="block p-4 border rounded hover:bg-gray-50">
              <span className="font-semibold">Project {p.number}</span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}



