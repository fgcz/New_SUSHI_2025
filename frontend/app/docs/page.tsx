export default function DocsHomePage() {
  return (
    <div className="prose max-w-none">
      <h1>Documentation</h1>
      <p className="text-lg text-gray-600">
        Welcome to the Sushi Frontend documentation. Here you'll find comprehensive guides and references for the codebase.
      </p>
      
      <h2>Available Documentation</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 not-prose">
        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Type System</h3>
          <p className="text-gray-600 mb-4">
            Comprehensive guide to all TypeScript types, their usage, and import patterns.
          </p>
          <a 
            href="/docs/types" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Type Documentation →
          </a>
        </div>
        
        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">jsTree Integration</h3>
          <p className="text-gray-600 mb-4">
            Complete implementation guide for jsTree with Next.js, including SSR solutions and type definitions.
          </p>
          <a 
            href="/docs/jstree" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View jsTree Documentation →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Loading Patterns</h3>
          <p className="text-gray-600 mb-4">
            React loading strategies: Suspense vs if-else vs loading.tsx with performance analysis.
          </p>
          <a 
            href="/docs/loading-patterns" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Loading Patterns →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Dynamic Forms</h3>
          <p className="text-gray-600 mb-4">
            Implementation guide for dynamic form generation system with external API definitions.
          </p>
          <a 
            href="/docs/dynamic-forms" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Dynamic Forms →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Providers</h3>
          <p className="text-gray-600 mb-4">
            Explanation about providers AuthProvider and QueryProvider used in app/layout.tsx
          </p>
          <a 
            href="/docs/providers" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Providers
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Pagination Architecture</h3>
          <p className="text-gray-600 mb-4">
            How our URL-driven pagination and search system works with hooks and TanStack Query.
          </p>
          <a 
            href="/docs/pagination" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Pagination Guide →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Table Editing System</h3>
          <p className="text-gray-600 mb-4">
            Complete architecture guide for the editable table system used for sample data manipulation.
          </p>
          <a 
            href="/docs/table-editing" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Table Editing Guide →
          </a>
        </div>

      </div>

    </div>
  );
}
