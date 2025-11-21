'use client';

import Link from 'next/link';
import { useState } from 'react';

export default function DocsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [sidebarOpen, setSidebarOpen] = useState(true);

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm border-b">
        <div className="container mx-auto px-6 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <Link href="/" className="text-blue-600 hover:text-blue-800">
                ← Back to App
              </Link>
              <button
                onClick={() => setSidebarOpen(!sidebarOpen)}
                className="p-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-md"
                title={sidebarOpen ? "Collapse sidebar" : "Expand sidebar"}
              >
                <svg 
                  className="w-5 h-5" 
                  fill="none" 
                  stroke="currentColor" 
                  viewBox="0 0 24 24"
                >
                  {sidebarOpen ? (
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 19l-7-7 7-7M21 12H3" />
                  ) : (
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
                  )}
                </svg>
              </button>
              <h1 className="text-2xl font-bold text-gray-900">Documentation</h1>
            </div>
          </div>
        </div>
      </header>

      <div className="container mx-auto px-6 py-8">
        <div className={`flex ${sidebarOpen ? 'gap-8' : 'gap-0'}`}>
          {/* Collapsible Sidebar Navigation */}
          {sidebarOpen && (
            <aside className="w-64 flex-shrink-0 transition-all duration-300 ease-in-out">
              <nav className="bg-white rounded-lg shadow-sm p-4 h-fit sticky top-8">
                <h2 className="font-semibold text-gray-900 mb-4">Documentation</h2>
                <ul className="space-y-2">
                  <li>
                    <Link 
                      href="/docs" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Overview
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/types" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Type System
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/jstree" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      jsTree Integration
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/loading-patterns" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Loading Patterns
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/dynamic-forms" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Dynamic Forms
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/providers" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Providers
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/pagination" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Pagination Architecture
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/table-editing" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Table Editing System
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/linting" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Linting System
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/test-strategy" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Test Strategy
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/test-layers" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Test Layers
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/backend-api" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Backend API Endpoints
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/multiple-ui-triggers" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Multiple UI Triggers
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/props-immutability" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      Props Immutability
                    </Link>
                  </li>
                  <li>
                    <Link 
                      href="/docs/state-management" 
                      className="block px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                    >
                      State Management
                    </Link>
                  </li>
                </ul>
              </nav>
            </aside>
          )}

          {/* Main Content */}
          <main className="flex-1 bg-white rounded-lg shadow-sm">
            <div className="p-8">
              {children}
            </div>
          </main>
        </div>
      </div>
    </div>
  );
}
