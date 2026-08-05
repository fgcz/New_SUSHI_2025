export default function DocsHomePage() {
  return (
    <div className="prose max-w-none">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 not-prose">
        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Architecture</h3>
          <p className="text-gray-600 mb-4">
            Folder structure, technology stack, data flow patterns, and architectural decisions.
          </p>
          <a
            href="/docs/architecture"
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View Architecture →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Type System</h3>
          <p className="text-gray-600 mb-4">
            Comprehensive guide to all TypeScript types, their usage, and import patterns.
          </p>
          <a 
            href="/docs/types" 
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View Type Documentation →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">API System</h3>
          <p className="text-gray-600 mb-4">
            Documentation to all backend API calls
          </p>
          <a
            href="/docs/api"
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View API Documentation →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Hooks</h3>
          <p className="text-gray-600 mb-4">
            Custom React hooks documentation covering data fetching, URL state, pagination, and form handling.
          </p>
          <a
            href="/docs/hooks"
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View Hooks Documentation →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Testing</h3>
          <p className="text-gray-600 mb-4">
            Overview of API layer, hook layer, and integration testing approaches with practical examples and focus areas.
          </p>
          <a 
            href="/docs/testing" 
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View Testing Documentation 
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Loading Patterns</h3>
          <p className="text-gray-600 mb-4">
            React loading strategies: Suspense vs if-else vs loading.tsx with performance analysis.
          </p>
          <a 
            href="/docs/loading-patterns" 
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View Loading Patterns
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Dynamic Forms</h3>
          <p className="text-gray-600 mb-4">
            Implementation guide for dynamic form generation system with external API definitions.
          </p>
          <a 
            href="/docs/dynamic-forms" 
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
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
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
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
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View Pagination Guide →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Hands On Table</h3>
          <p className="text-gray-600 mb-4">
            Hands on table documentation for sample editing.
          </p>
          <a 
            href="/docs/handsontable" 
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View Handsontable Documentation
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Linting System</h3>
          <p className="text-gray-600 mb-4">
            Complete guide to the code linting and formatting system, covering ESLint, Prettier, TypeScript, and Coc.nvim integration.
          </p>
          <a 
            href="/docs/linting" 
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View Linting System →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">Multiple UI Triggers</h3>
          <p className="text-gray-600 mb-4">
            Analysis of NextJS rendering cycles and React Query data fetching patterns that cause multiple component re-renders.
          </p>
          <a 
            href="/docs/multiple-ui-triggers" 
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View UI Triggers Guide →
          </a>
        </div>

        <div className="border rounded-lg p-6 hover:shadow-md transition-shadow">
          <h3 className="text-lg font-semibold mb-2">State Management</h3>
          <p className="text-gray-600 mb-4">
            Guide to state management and data persistence between pages using localStorage, React Context, and server-side sessions.
          </p>
          <a 
            href="/docs/state-management" 
            className="inline-flex items-center text-brand-600 hover:text-brand-800"
          >
            View State Management →
          </a>
        </div>

      </div>

    </div>
  );
}
