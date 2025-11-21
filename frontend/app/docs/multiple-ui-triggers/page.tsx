import fs from 'fs';
import path from 'path';
import DocsMarkdown from '../components/DocsMarkdown';

export default async function MultipleUITriggersPage() {
  // Read the multiple-ui-triggers.md file from the docs folder
  const docsPath = path.join(process.cwd(), 'docs', 'multiple-ui-triggers.md');
  
  try {
    const markdownContent = fs.readFileSync(docsPath, 'utf8');
    
    return <DocsMarkdown content={markdownContent} />;
  } catch (error) {
    return (
      <div className="prose max-w-none">
        <h1>Error Loading Documentation</h1>
        <p className="text-red-600">
          Could not load the multiple UI triggers documentation. Please make sure the file exists at: <code>docs/multiple-ui-triggers.md</code>
        </p>
        <p className="text-gray-600">
          Error: {error instanceof Error ? error.message : 'Unknown error'}
        </p>
      </div>
    );
  }
}