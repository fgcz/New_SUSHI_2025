import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeHighlight from 'rehype-highlight';
import 'highlight.js/styles/github.css';

interface DocsMarkdownProps {
  content: string;
  className?: string;
}

/**
 * Reusable markdown component for documentation pages with consistent styling
 */
export default function DocsMarkdown({ content, className = "prose prose-lg max-w-none" }: DocsMarkdownProps) {
  return (
    <div className={className}>
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
          h5: ({ children }) => (
            <h5 className="mt-4 mb-2 text-base font-medium text-gray-700">
              {children}
            </h5>
          ),
          h6: ({ children }) => (
            <h6 className="mt-3 mb-2 text-sm font-medium text-gray-600">
              {children}
            </h6>
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
          code: ({ node, inline, className, children, ...props }) => {
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
          // Custom styling for blockquotes
          blockquote: ({ children }) => (
            <blockquote className="border-l-4 border-blue-500 pl-4 italic text-gray-700 bg-blue-50 p-4 rounded-r-lg">
              {children}
            </blockquote>
          ),
          // Custom styling for lists
          ul: ({ children }) => (
            <ul className="space-y-1 list-disc list-inside">
              {children}
            </ul>
          ),
          ol: ({ children }) => (
            <ol className="space-y-1 list-decimal list-inside">
              {children}
            </ol>
          ),
          // Custom styling for paragraphs
          p: ({ children }) => (
            <p className="mb-4 text-gray-700 leading-relaxed">
              {children}
            </p>
          ),
          // Handle line breaks in table cells
          br: () => <br className="my-1" />
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );
}