export default function DocsHomePage() {
  return (
    <div className="prose max-w-none">
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

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Linting System</h3>
          <p className="text-gray-600 mb-4">
            Complete guide to the code linting and formatting system, covering ESLint, Prettier, TypeScript, and Coc.nvim integration.
          </p>
          <a 
            href="/docs/linting" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Linting System →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Test Strategy</h3>
          <p className="text-gray-600 mb-4">
            Testing strategy and implementation plan covering unit tests, integration tests, best practices, and tooling setup.
          </p>
          <a 
            href="/docs/test-strategy" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Test Strategy →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Test Layers</h3>
          <p className="text-gray-600 mb-4">
            Overview of API layer, hook layer, and integration testing approaches with practical examples and focus areas.
          </p>
          <a 
            href="/docs/test-layers" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Test Layers →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Backend API Endpoints</h3>
          <p className="text-gray-600 mb-4">
            Complete reference for all available REST API endpoints including authentication, projects, datasets, jobs, and configuration.
          </p>
          <a 
            href="/docs/backend-api" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View API Documentation →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Multiple UI Triggers</h3>
          <p className="text-gray-600 mb-4">
            Analysis of NextJS rendering cycles and React Query data fetching patterns that cause multiple component re-renders.
          </p>
          <a 
            href="/docs/multiple-ui-triggers" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View UI Triggers Guide →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Props Immutability</h3>
          <p className="text-gray-600 mb-4">
            Why React props should never be mutated and how to properly handle editable data with local state patterns.
          </p>
          <a 
            href="/docs/props-immutability" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View Props Guide →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">State Management</h3>
          <p className="text-gray-600 mb-4">
            Guide to state management and data persistence between pages using localStorage, React Context, and server-side sessions.
          </p>
          <a 
            href="/docs/state-management" 
            className="inline-flex items-center text-blue-600 hover:text-blue-800"
          >
            View State Management →
          </a>
        </div>

      </div>

    </div>
  );
}
