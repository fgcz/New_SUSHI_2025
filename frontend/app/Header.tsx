'use client';

import Link from 'next/link';
import { useAuth } from '@/providers/AuthContext';
import { useParams, useRouter } from 'next/navigation';
import { useState, useEffect } from 'react';
import { useProjectList } from '@/lib/hooks';
import { projectApi } from '@/lib/api';

// Authentication status component
const AuthStatus = () => {
  const { authStatus, loading, error } = useAuth();

  if (loading) {
    return (
      <div className="bg-brand-50 border border-brand-200 rounded-lg p-2 mb-4">
        <div className="flex items-center">
          <div className="animate-spin rounded-full h-3 w-3 border-b-2 border-brand-600 mr-2"></div>
          <span className="text-brand-800 text-xs">Loading auth...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-2 mb-4">
        <div className="flex items-center">
          <span className="text-red-800 text-xs">Auth Error: {error}</span>
        </div>
      </div>
    );
  }

  if (!authStatus || !authStatus.authentication_skipped) {
    return null;
  }

  return (
    <div className="bg-green-50 border border-green-200 rounded-lg p-2 mb-4">
      <div className="flex items-center justify-between">
        <div>
          <span className="text-green-800 font-semibold text-xs">✅ Auth Skipped</span>
          <span className="text-green-700 text-xs ml-2">
            User: {authStatus.current_user || 'Anonymous'}
          </span>
        </div>
        <Link 
          href="/auth/login_options" 
          className="text-green-600 hover:text-green-800 text-xs underline"
          target="_blank"
        >
          Options
        </Link>
      </div>
    </div>
  );
};

export default function Header() {
  const { authStatus, logout, loading } = useAuth();
  const params = useParams<{ projectNumber?: string }>();
  const router = useRouter();
  const [searchQuery, setSearchQuery] = useState('');
  const [datasetSearchQuery, setDatasetSearchQuery] = useState('');
  const [showProjectsDropdown, setShowProjectsDropdown] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const { userProjects, isLoading: projectsLoading } = useProjectList();

  const projectNumber = params?.projectNumber ? Number(params.projectNumber) : null;
  const userName = authStatus?.current_user || "Guest";

  // Prepopulate search with current project number
  useEffect(() => {
    if (projectNumber) {
      setSearchQuery(projectNumber.toString());
    }
  }, [projectNumber]);

  // Auto-dismiss error message after 5 seconds
  useEffect(() => {
    if (errorMessage) {
      const timer = setTimeout(() => setErrorMessage(null), 5000);
      return () => clearTimeout(timer);
    }
  }, [errorMessage]);

  // Show loading screen while checking authentication
  if (loading) {
    return (
      <header className="bg-white shadow-sm border-b border-gray-200 sticky top-0 z-50">
        <div className="container mx-auto px-6 py-3 flex justify-between items-center">
          <div className="text-3xl font-bold" style={{fontFamily: "Comic Sans MS, cursive, sans-serif"}}>
            <h1>Sushi</h1>
          </div>
          <div className="flex items-center">
            <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-brand-600 mr-2"></div>
            <span className="text-gray-600 text-sm">Loading...</span>
          </div>
        </div>
      </header>
    );
  }

  const handleLogout = (e: React.MouseEvent) => {
    e.preventDefault();
    logout();
  };

  const handleSearchSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmedQuery = searchQuery.trim();
    if (trimmedQuery) {
      router.push(`/projects/${trimmedQuery}`);
    }
  };

  const handleDatasetSearchSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmedQuery = datasetSearchQuery.trim();
    if (!trimmedQuery) return;

    if (!/^\d+$/.test(trimmedQuery)) {
      setErrorMessage('Dataset ID must be a number');
      return;
    }

    const datasetId = Number(trimmedQuery);
    try {
      const { projectId } = await projectApi.validateDatasetId(userName, datasetId);
      setErrorMessage(null);
      router.push(`/projects/${projectId}/datasets/${datasetId}`);
      setDatasetSearchQuery('');
    } catch (error) {
      setErrorMessage(`Dataset ${datasetId} not found`);
      // Stay on current page - don't navigate
    }
  };

  const toggleProjectsDropdown = (e: React.MouseEvent) => {
    e.preventDefault();
    setShowProjectsDropdown(!showProjectsDropdown);
  };

  return (
    <div className="sticky top-0 z-50">
      <header className="bg-white shadow-sm border-b border-gray-200">
        <div className="container mx-auto py-2 flex justify-between items-center">
          <div className="flex items-center">
            <Link href="/" className="text-3xl font-bold hover:text-brand-600 transition-colors mr-4" style={{fontFamily: "Comic Sans MS, cursive, sans-serif"}}>
              <h1>Sushi</h1>
            </Link>
            
            {/* Projects dropdown */}
            <div className="relative">
              <button 
                onClick={toggleProjectsDropdown}
                className="text-gray-600 hover:text-brand-600 flex items-center space-x-1 px-2 py-1"
              >
                <span>Projects</span>
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              </button>
            
            {showProjectsDropdown && (
              <div className="absolute top-full left-0 mt-1 bg-white border border-gray-200 rounded-md shadow-lg z-50 min-w-48">
                {projectsLoading ? (
                  <div className="px-4 py-2 text-gray-500">Loading...</div>
                ) : userProjects && userProjects.projects.length > 0 ? (
                  <>
                    {userProjects.projects.map((projectNumber) => (
                      <Link
                        key={projectNumber}
                        href={`/projects/${projectNumber}`}
                        className="block px-4 py-2 text-gray-700 hover:bg-gray-100"
                        onClick={() => setShowProjectsDropdown(false)}
                      >
                        Project {projectNumber}
                      </Link>
                    ))}
                  </>
                ) : (
                  <div className="px-4 py-2 text-gray-500">No projects available</div>
                )}
              </div>
            )}
            </div>
            
            {/* Project Search */}
            <form onSubmit={handleSearchSubmit} className="flex items-center">
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Project #..."
                className="px-2 py-1 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent text-sm w-24"
              />
            </form>

            {/* Dataset ID Search */}
            {/* <form onSubmit={handleDatasetSearchSubmit} className="flex items-center ml-2"> */}
            {/*   <input */}
            {/*     type="text" */}
            {/*     value={datasetSearchQuery} */}
            {/*     onChange={(e) => setDatasetSearchQuery(e.target.value)} */}
            {/*     placeholder="Dataset ID" */}
            {/*     className="px-2 py-1 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent text-sm w-24" */}
            {/*   /> */}
            {/* </form> */}
          </div>
          
          <nav className="flex items-center space-x-4">
            {projectNumber && (
              <Link href={`/projects/${projectNumber}/datasets`} className="text-gray-600 hover:text-brand-600">DataSets</Link>
            )}
            <Link href={`/projects/${projectNumber}/datasets/import`} className="text-gray-600 hover:text-brand-600">Import</Link>
            <Link href={`/projects/${projectNumber}/jobs`} className="text-gray-600 hover:text-brand-600">Jobs</Link>
            <Link href={`/files/p${projectNumber}`} className="text-gray-600 hover:text-brand-600">gStore</Link>
            <Link href="/docs" className="text-gray-600 hover:text-brand-600">Docs</Link>
            <Link href="/dataset/list" className="text-gray-600 hover:text-brand-600">Find</Link>
            <Link href="/help" className="text-gray-600 hover:text-brand-600">Help</Link>
            <div className="border-l border-gray-300 h-6"></div>
            {projectNumber && (
              <span className="font-semibold">Project {projectNumber}</span>
            )}
            <span className="text-gray-700">
            Hi, {userName}
            {/* Auth Skipped indicator commented out
            {authStatus?.authentication_skipped ? (
              <span className="text-green-600 ml-1">| Auth Skipped</span>
            ) : (
              <button
                onClick={handleLogout}
                className="text-brand-600 hover:underline ml-1 bg-transparent border-none cursor-pointer"
              >
                | Sign out
              </button>
            )}
            */}
          </span>
        </nav>
      </div>
      </header>
      
      {/* Close dropdown when clicking outside */}
      {showProjectsDropdown && (
        <div 
          className="fixed inset-0 z-40" 
          onClick={() => setShowProjectsDropdown(false)}
        />
      )}
      {/* Error message banner */}
      {errorMessage && (
        <div className="bg-red-50 border-b border-red-200">
          <div className="container mx-auto px-6 py-2 flex items-center justify-between">
            <div className="flex items-center">
              <span className="text-red-600 mr-2">⚠</span>
              <span className="text-red-800 text-sm">{errorMessage}</span>
            </div>
            <button
              onClick={() => setErrorMessage(null)}
              className="text-red-600 hover:text-red-800 text-sm font-medium"
            >
              Dismiss
            </button>
          </div>
        </div>
      )}

      {/* Auth status commented out - header getting populated
      <div className="container mx-auto px-6">
        <AuthStatus />
      </div>
      */}
    </div>
  );
}
