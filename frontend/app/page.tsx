'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useAuth } from '@/contexts/AuthContext';

// Define the type for a menu item
interface MenuItem {
  title: string;
  description: string;
  link: string;
  icon: string;
}

const menuItems: MenuItem[] = [
  {
    title: 'DataSets',
    description: 'You can see, edit and delete DataSets.\nYou can execute a SUSHI application.',
    link: '/projects/1001/datasets', //TODO Placeholder link
    icon: '/images/tamago.png',
  },
  {
    title: 'Import DataSet',
    description: 'Import a DataSet from .tsv file.',
    link: '/import', //TODO Placeholder link
    icon: '/images/tako.png',
  },
  {
    title: 'Check Jobs',
    description: 'Check your submitted jobs and the status.',
    link: '/jobs', //TODO Placeholder link
    icon: '/images/maguro.png',
  },
  {
    title: 'gStore',
    description: 'Show result folder. You can see and download files of result data.',
    link: '/gstore', //TODO Placeholder link
    icon: '/images/uni.png',
  },
];

// A component for a single menu card
// The description is split by newline characters to render <br /> tags
const MenuCard = ({ item }: { item: MenuItem }) => (
  <div className="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow duration-300 ease-in-out border border-gray-200">
    <Link href={item.link} className="block p-6 text-center">
      <div className="flex flex-col items-center">
        <div className="w-32 h-32 relative mb-4">
            <Image src={item.icon} alt={`${item.title} icon`} fill className="object-contain" />
        </div>
        <h3 className="text-xl font-semibold text-blue-700 mb-2">{item.title}</h3>
        <p className="text-gray-600 text-sm">
            {item.description.split('\n').map((line, index) => (
              <span key={index}>{line}{index !== item.description.split('\n').length - 1 && <br />}</span>
            ))}
        </p>
      </div>
    </Link>
  </div>
);

// Authentication status component
const AuthStatus = () => {
  const { authStatus, loading, error } = useAuth();

  if (loading) {
    return (
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
        <div className="flex items-center">
          <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600 mr-2"></div>
          <span className="text-blue-800">Loading authentication status...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
        <div className="flex items-center">
          <span className="text-red-800">Error: {error}</span>
        </div>
      </div>
    );
  }

  if (!authStatus) {
    return null;
  }

  if (authStatus.authentication_skipped) {
    return (
      <div className="bg-green-50 border border-green-200 rounded-lg p-4 mb-6">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-green-800 font-semibold">✅ Authentication Skipped</h3>
            <p className="text-green-700 text-sm">
              Welcome! Authentication is currently disabled. You can access the application without logging in.
            </p>
            <p className="text-green-700 text-sm mt-1">
              <strong>Current User:</strong> {authStatus.current_user || 'Anonymous'}
            </p>
          </div>
          <Link 
            href="/auth/login_options" 
            className="text-green-600 hover:text-green-800 text-sm underline"
            target="_blank"
          >
            View Auth Options
          </Link>
        </div>
      </div>
    );
  }

  // If authentication is required but user is not logged in, don't show this component
  if (!authStatus.current_user) {
    return null;
  }

  return (
    <div className="bg-green-50 border border-green-200 rounded-lg p-4 mb-6">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-green-800 font-semibold">✅ Authenticated</h3>
          <p className="text-green-700 text-sm">
            Welcome! You are successfully logged in.
          </p>
          <p className="text-green-700 text-sm mt-1">
            <strong>Current User:</strong> {authStatus.current_user}
          </p>
        </div>
      </div>
    </div>
  );
};

// The main dashboard page component
export default function Home() {
  const projectNumber = 1001; //TODO Hardcoded project number 
  const { authStatus, logout, loading } = useAuth();
  const userName = authStatus?.current_user || "Guest";

  const handleLogout = (e: React.MouseEvent) => {
    e.preventDefault();
    logout();
  };

  // Show loading screen while checking authentication
  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-2 text-gray-600">Loading...</p>
        </div>
      </div>
    );
  }

  // Don't render anything if authentication is required but user is not logged in
  // This prevents the flash of content before redirect
  if (authStatus && !authStatus.authentication_skipped && !authStatus.current_user) {
    return null;
  }

  // If no auth status yet, show loading
  if (!authStatus) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-2 text-gray-600">Loading...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col min-h-screen" style={{ backgroundColor: '#e0e5e9' }}>
      <header className="bg-white shadow-sm border-b-2 border-gray-200">
        <div className="container mx-auto px-6 py-3 flex justify-between items-center">
          <h1 className="text-3xl font-bold" style={{fontFamily: "Comic Sans MS, cursive, sans-serif"}}>Sushi</h1>
          <nav className="flex items-center space-x-4">
            <Link href="/datasets" className="text-gray-600 hover:text-blue-600">DataSets</Link>
            <Link href="/import" className="text-gray-600 hover:text-blue-600">Import</Link>
            <Link href="/jobs" className="text-gray-600 hover:text-blue-600">Jobs</Link>
            <Link href="/gstore" className="text-gray-600 hover:text-blue-600">gStore</Link>
            <Link href="/help" className="text-gray-600 hover:text-blue-600">Help</Link>
            <div className="border-l border-gray-300 h-6"></div>
            <span className="font-semibold">Project {projectNumber}</span>
            <span className="text-gray-700">
              Hi, {userName} | 
              {authStatus?.authentication_skipped ? (
                <Link href="/auth/login_options" className="text-blue-600 hover:underline ml-1">Auth Status</Link>
              ) : (
                <button 
                  onClick={handleLogout}
                  className="text-blue-600 hover:underline ml-1 bg-transparent border-none cursor-pointer"
                >
                  Sign out
                </button>
              )}
            </span>
          </nav>
        </div>
      </header>

      <main className="flex-grow container mx-auto px-6 py-10">
        <AuthStatus />
        <div className="bg-white p-8 rounded-lg shadow-inner" style={{ backgroundColor: 'rgba(255, 255, 255, 0.8)' }}>
            <h2 className="text-3xl font-bold text-gray-800 mb-8">
              Project {projectNumber}
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-8">
              {menuItems.map((item) => (
                <MenuCard key={item.title} item={item} />
              ))}
            </div>
        </div>
      </main>

      <footer className="py-4 mt-auto" style={{ backgroundColor: '#2c3e50', color: 'white' }}>
        <div className="container mx-auto px-6 text-center text-sm">
          SUSHI - produced by Functional Genomics Center Zurich and SIB
        </div>
      </footer>
    </div>
  );
}
