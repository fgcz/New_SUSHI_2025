import fs from 'fs';
import path from 'path';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeHighlight from 'rehype-highlight';
import 'highlight.js/styles/github.css';

export default async function DynamicFormsPage() {
  // Read the dynamic-forms.md file from the docs folder
  const docsPath = path.join(process.cwd(), 'docs', 'dynamic-forms.md');
  
  try {
    const markdownContent = fs.readFileSync(docsPath, 'utf8');
    
    return (
      <div className="prose prose-lg max-w-none">
        <ReactMarkdown 
          remarkPlugins={[remarkGfm]}
          rehypePlugins={[rehypeHighlight]}
          components={{
            // Custom styling for headers
            h1: ({ children }) => (
              <h1 className="mt-8 mb-6 text-3xl font-bold text-gray-900">
                {children}
              </h1>
            ),
            h2: ({ children }) => (
              <h2 className="mt-12 mb-6 pt-8 border-t border-gray-200 first:mt-8 first:border-t-0 first:pt-0 text-2xl font-bold">
                {children}
              </h2>
            ),
            h3: ({ children }) => (
              <h3 className="mt-8 mb-4 text-xl font-semibold text-gray-800">
                {children}
              </h3>
            ),
            h4: ({ children }) => (
              <h4 className="mt-6 mb-3 text-lg font-medium text-gray-700">
                {children}
              </h4>
            ),
            // Custom styling for tables
            table: ({ children }) => (
              <div className="overflow-x-auto">
                <table className="min-w-full border-collapse border border-gray-300">
                  {children}
                </table>
              </div>
            ),
            th: ({ children }) => (
              <th className="border border-gray-300 bg-gray-50 px-4 py-2 text-left font-semibold">
                {children}
              </th>
            ),
            td: ({ children }) => (
              <td className="border border-gray-300 px-4 py-2 align-top">
                <div className="space-y-1">
                  {children}
                </div>
              </td>
            ),
            // Custom styling for code blocks
            code: ({ node, inline, className, children, ...props }: any) => {
              if (inline) {
                return (
                  <code className="bg-gray-100 px-1 py-0.5 rounded text-sm font-mono" {...props}>
                    {children}
                  </code>
                );
              }
              return (
                <code className={className} {...props}>
                  {children}
                </code>
              );
            },
            // Handle line breaks in table cells
            br: () => <br className="my-1" />
          }}
        >
          {markdownContent}
        </ReactMarkdown>
      </div>
    );
  } catch (error) {
    return (
      <div className="prose max-w-none">
        <h1>Error Loading Documentation</h1>
        <p className="text-red-600">
          Could not load the dynamic forms documentation. Please make sure the file exists at: <code>docs/dynamic-forms.md</code>
        </p>
        <p className="text-gray-600">
          Error: {error instanceof Error ? error.message : 'Unknown error'}
        </p>
      </div>
    );
  }
}