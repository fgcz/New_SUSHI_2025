import fs from 'fs';
import path from 'path';
import DocsMarkdown from '../components/DocsMarkdown';

export default async function BackendAPIDocsPage() {
  // Read the backend-api-endpoints.md file from the docs folder
  const docsPath = path.join(process.cwd(), 'docs', 'backend-api-endpoints.md');
  
  try {
    const markdownContent = fs.readFileSync(docsPath, 'utf8');
    
    return <DocsMarkdown content={markdownContent} />;
  } catch (error) {
    return (
      <div className="prose max-w-none">
        <h1>Error Loading Documentation</h1>
        <p className="text-red-600">
          Could not load the backend API documentation. Please make sure the file exists at: <code>docs/backend-api-endpoints.md</code>
        </p>
        <p className="text-gray-600">
          Error: {error instanceof Error ? error.message : 'Unknown error'}
        </p>
      </div>
    );
  }
}