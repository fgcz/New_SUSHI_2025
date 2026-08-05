'use client';

import { useState, useEffect, useMemo, useRef } from 'react';

interface TreeNode {
  id: number;
  name: string;
  parent: number | '#';
  children?: TreeNode[];
}

interface ParentSelectorProps {
  treeNodes: any[];
  selectedId: number | null;
  onSelect: (id: number | null) => void;
  searchQuery: string;
}

// ── Icons (matches DatasetTreeRcTree) ────────────────────────────────

const IconChevronRight = () => (
  <svg width="14" height="14" viewBox="0 0 12 12" fill="none" stroke="currentColor"
    strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
    <path d="M4.5 2.5L8 6L4.5 9.5" />
  </svg>
);

const IconChevronDown = () => (
  <svg width="14" height="14" viewBox="0 0 12 12" fill="none" stroke="currentColor"
    strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
    <path d="M2.5 4.5L6 8L9.5 4.5" />
  </svg>
);

const IconFolderClosed = () => (
  <svg width="17" height="17" viewBox="0 0 16 16" fill="currentColor" style={{ color: '#2A9391' }}>
    <path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75z" />
  </svg>
);

// ── Helpers ──────────────────────────────────────────────────────────

const GUIDE_COLOR = '#6CD3D1';

function HighlightedText({ text, query }: { text: string; query?: string }) {
  if (!query?.trim()) return <>{text}</>;
  const q = query.trim();
  const idx = text.toLowerCase().indexOf(q.toLowerCase());
  if (idx === -1) return <>{text}</>;
  return (
    <>
      {text.slice(0, idx)}
      <mark className="bg-yellow-100 text-yellow-800 rounded-sm px-0.5 not-italic">{text.slice(idx, idx + q.length)}</mark>
      {text.slice(idx + q.length)}
    </>
  );
}

function collectAllIds(nodes: TreeNode[]): Set<number> {
  const ids = new Set<number>();
  const walk = (ns: TreeNode[]) => {
    for (const n of ns) { ids.add(n.id); if (n.children?.length) walk(n.children); }
  };
  walk(nodes);
  return ids;
}

// ── Node ─────────────────────────────────────────────────────────────

function TreeNodeRow({
  node,
  depth,
  isLast,
  selectedId,
  onSelect,
  expandedIds,
  toggleExpand,
  searchQuery,
}: {
  node: TreeNode;
  depth: number;
  isLast: boolean;
  selectedId: number | null;
  onSelect: (id: number | null) => void;
  expandedIds: Set<number>;
  toggleExpand: (id: number) => void;
  searchQuery: string;
}) {
  const hasChildren = (node.children?.length ?? 0) > 0;
  const isExpanded = expandedIds.has(node.id);
  const isSelected = selectedId === node.id;

  return (
    <div>
      <div
        className={`group flex items-center gap-2 py-1.5 pr-2 cursor-pointer select-none transition-colors duration-75 ${
          isSelected ? 'bg-brand-50' : 'hover:bg-gray-50'
        }`}
        onClick={() => onSelect(isSelected ? null : node.id)}
      >
        <span className="flex-shrink-0 flex items-center leading-none">
          <IconFolderClosed />
        </span>

        {hasChildren ? (
          <span
            className="flex-shrink-0 text-gray-400 group-hover:text-gray-600 transition-colors"
            onClick={(e) => { e.stopPropagation(); toggleExpand(node.id); }}
          >
            {isExpanded ? <IconChevronDown /> : <IconChevronRight />}
          </span>
        ) : (
          <span className="w-[14px] flex-shrink-0" />
        )}

        <div
          className={`w-3.5 h-3.5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-colors ${
            isSelected ? 'border-brand-600 bg-brand-600' : 'border-gray-300'
          }`}
        >
          {isSelected && <div className="w-1 h-1 rounded-full bg-white" />}
        </div>

        <span className={`text-sm font-medium truncate flex-1 min-w-0 transition-colors ${
          isSelected ? 'text-brand-700' : 'text-gray-900'
        }`}>
          <HighlightedText text={node.name} query={searchQuery} />
        </span>
      </div>

      {hasChildren && isExpanded && (
        <div className="relative ml-5">
          <div style={{ position: 'absolute', left: 5, top: 0, bottom: 12, width: 1, backgroundColor: GUIDE_COLOR }} />
          {node.children!.map((child, idx) => {
            const childIsLast = idx === node.children!.length - 1;
            return (
              <div key={child.id} className="relative pl-5">
                <div style={{ position: 'absolute', left: 5, top: 14, width: 14, height: 1, backgroundColor: GUIDE_COLOR }} />
                {childIsLast && (
                  <div style={{ position: 'absolute', left: 5, top: 15, bottom: 0, width: 1, backgroundColor: 'white' }} />
                )}
                <TreeNodeRow
                  node={child}
                  depth={depth + 1}
                  isLast={childIsLast}
                  selectedId={selectedId}
                  onSelect={onSelect}
                  expandedIds={expandedIds}
                  toggleExpand={toggleExpand}
                  searchQuery={searchQuery}
                />
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ── Main component ───────────────────────────────────────────────────

export default function ParentSelector({ treeNodes, selectedId, onSelect, searchQuery }: ParentSelectorProps) {
  const [expandedIds, setExpandedIds] = useState<Set<number>>(new Set());
  const initializedRef = useRef(false);

  // Build tree
  const roots = useMemo(() => {
    const nodeMap = new Map<number, TreeNode>();
    const rootNodes: TreeNode[] = [];

    treeNodes.forEach(node => {
      nodeMap.set(node.id, { id: node.id, name: node.name || `Dataset ${node.id}`, parent: node.parent, children: [] });
    });
    treeNodes.forEach(node => {
      const treeNode = nodeMap.get(node.id);
      if (!treeNode) return;
      if (node.parent === '#') rootNodes.push(treeNode);
      else nodeMap.get(Number(node.parent))?.children?.push(treeNode);
    });

    return rootNodes;
  }, [treeNodes]);

  // Start fully expanded
  useEffect(() => {
    if (!initializedRef.current && roots.length > 0) {
      initializedRef.current = true;
      setExpandedIds(collectAllIds(roots));
    }
  }, [roots]);

  // Expand all on search
  useEffect(() => {
    if (searchQuery.trim()) setExpandedIds(collectAllIds(roots));
  }, [searchQuery, roots]);

  // Filter on search
  const filteredRoots = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return roots;

    const filter = (nodes: TreeNode[], parentMatches = false): TreeNode[] =>
      nodes.flatMap(node => {
        const selfMatch = node.name.toLowerCase().includes(q);
        const include = parentMatches || selfMatch;
        const filteredChildren = filter(node.children ?? [], include);
        if (include || filteredChildren.length > 0) return [{ ...node, children: filteredChildren }];
        return [];
      });

    return filter(roots);
  }, [roots, searchQuery]);

  const toggleExpand = (id: number) => {
    setExpandedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  return (
    <div className="border border-gray-200 rounded-lg bg-white max-h-56 overflow-y-auto">
      {filteredRoots.length === 0 ? (
        <div className="p-4 text-gray-500 text-sm text-center">No datasets found</div>
      ) : (
        <div className="py-1 px-1">
          {filteredRoots.map((node, idx) => (
            <TreeNodeRow
              key={node.id}
              node={node}
              depth={0}
              isLast={idx === filteredRoots.length - 1}
              selectedId={selectedId}
              onSelect={onSelect}
              expandedIds={expandedIds}
              toggleExpand={toggleExpand}
              searchQuery={searchQuery}
            />
          ))}
        </div>
      )}
    </div>
  );
}
