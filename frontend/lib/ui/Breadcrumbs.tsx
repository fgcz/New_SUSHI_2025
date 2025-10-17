import Link from 'next/link';

interface BreadcrumbItem {
  label: string;
  href?: string;
  active?: boolean;
}

interface BreadcrumbsProps {
  items: BreadcrumbItem[];
}

export default function Breadcrumbs({ items }: BreadcrumbsProps) {
  const elements = [];
  
  items.forEach((item, index) => {
    if (index > 0) {
      elements.push(<li key={`sep-${index}`}>/</li>);
    }
    
    elements.push(
      <li key={`item-${index}`}>
        {item.href && !item.active ? (
          <Link 
            href={item.href} 
            className="hover:text-gray-700 transition-colors"
          >
            {item.label}
          </Link>
        ) : (
          <span className={item.active ? "text-gray-900 font-medium" : ""}>
            {item.label}
          </span>
        )}
      </li>
    );
  });

  return (
    <nav className="mb-8">
      <ol className="flex items-center space-x-2 text-sm text-gray-500">
        {elements}
      </ol>
    </nav>
  );
}

export type { BreadcrumbItem, BreadcrumbsProps };
