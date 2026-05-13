'use client';

import { useMemo, useState, useEffect, useRef } from 'react';
import Tree from 'rc-tree';
import type { Key } from 'rc-tree/es/interface';
import 'rc-tree/assets/index.css';

// ── Shared types ─────────────────────────────────────────────────────

interface DatasetTreeProps {
  treeNodes: any[];
  projectNumber: number;
  selectedIds?: Set<number>;
  onSelectionChange?: (selected: Set<number>) => void;
  searchQuery?: string;
  currentDatasetId?: number;
  variant?: 'rctree' | 'geist';
  noFade?: boolean;
}

interface RcTreeNode {
  key: string;
  title: string;
  comment?: string;
  childrenCount: number;
  href: string;
  originalId: number;
  children?: RcTreeNode[];
}

// ── Helpers ──────────────────────────────────────────────────────────

function buildRoots(treeNodes: any[], projectNumber: number): RcTreeNode[] {
  const nodeMap = new Map<string, RcTreeNode>();
  const rootNodes: RcTreeNode[] = [];
  for (const n of treeNodes) {
    nodeMap.set(String(n.id), {
      key: String(n.id),
      title: n.name ?? `#${n.id}`,
      comment: n.comment,
      childrenCount: n.children_count ?? 0,
      href: `/projects/${projectNumber}/datasets/${n.id}`,
      originalId: n.id,
      children: [],
    });
  }
  for (const n of treeNodes) {
    const node = nodeMap.get(String(n.id));
    if (!node) continue;
    if (n.parent === '#') rootNodes.push(node);
    else nodeMap.get(String(n.parent))?.children?.push(node);
  }
  return rootNodes;
}

function filterNodes(nodes: RcTreeNode[], query: string): RcTreeNode[] {
  const q = query.trim().toLowerCase();
  if (!q) return nodes;
  return nodes
    .map((node) => {
      const filteredChildren = filterNodes(node.children ?? [], q);
      const selfMatch = node.title.toLowerCase().includes(q);
      if (selfMatch || filteredChildren.length > 0) return { ...node, children: filteredChildren };
      return null;
    })
    .filter(Boolean) as RcTreeNode[];
}

function collectAllKeys(nodes: RcTreeNode[]): Set<string> {
  const keys = new Set<string>();
  const walk = (ns: RcTreeNode[]) => {
    for (const n of ns) { keys.add(n.key); if (n.children?.length) walk(n.children); }
  };
  walk(nodes);
  return keys;
}

// ── SVG Icons ────────────────────────────────────────────────────────

const IconChevronRight = () => (
  <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor"
    strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
    <path d="M4.5 2.5L8 6L4.5 9.5" />
  </svg>
);

const IconChevronDown = () => (
  <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor"
    strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
    <path d="M2.5 4.5L6 8L9.5 4.5" />
  </svg>
);

const IconFolderClosed = () => (
  <svg width="15" height="15" viewBox="0 0 16 16" fill="currentColor" className="text-amber-400">
    <path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75z" />
  </svg>
);

const IconFolderOpen = () => (
  <svg width="15" height="15" viewBox="0 0 16 16" fill="currentColor" className="text-amber-300">
    <path d="M.513 1.513A1.75 1.75 0 0 1 1.75 1h3.5c.55 0 1.07.26 1.4.7l.9 1.2a.25.25 0 0 0 .2.1H14.25c.966 0 1.75.784 1.75 1.75v8.5A1.75 1.75 0 0 1 14.25 15H1.75A1.75 1.75 0 0 1 0 13.25V2.75c0-.464.184-.91.513-1.237z" />
    <path fill="rgba(0,0,0,.15)" d="M0 6h16v7.25A1.75 1.75 0 0 1 14.25 15H1.75A1.75 1.75 0 0 1 0 13.25V6z" />
  </svg>
);

const IconFile = () => (
  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-400">
    <path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z" />
    <polyline points="13 2 13 9 20 9" />
    <line x1="16" y1="13" x2="8" y2="13" />
    <line x1="16" y1="17" x2="8" y2="17" />
  </svg>
);

// ── Shared node props ─────────────────────────────────────────────────

interface SharedNodeProps {
  expandedKeys: Set<string>;
  toggleExpand: (key: string) => void;
  currentDatasetId?: number;
  hasCheckboxes: boolean;
  checkedIds: Set<number>;
  onCheckChange: (id: number, checked: boolean) => void;
  noFade?: boolean;
}

// ════════════════════════════════════════════════════════════════════
//  VARIANT: GEIST
// ════════════════════════════════════════════════════════════════════

function GeistNode({ node, depth, isLast, ...shared }: { node: RcTreeNode; depth: number; isLast: boolean } & SharedNodeProps) {
  const { expandedKeys, toggleExpand, currentDatasetId, hasCheckboxes, checkedIds, onCheckChange, noFade } = shared;
  const isExpanded = expandedKeys.has(node.key);
  const hasChildren = (node.children?.length ?? 0) > 0;
  const isCurrent = currentDatasetId === node.originalId;
  const guideColor = '#6CD3D1';

  return (
    <div>
      <div
        className={`
          group flex items-center gap-2 py-[5px] pr-2 cursor-pointer select-none
          transition-colors duration-75 min-w-0
          ${isCurrent ? 'bg-brand-50' : 'hover:bg-gray-50'}
        `}
        onClick={() => { if (hasChildren) toggleExpand(node.key); }}
      >
        {hasCheckboxes && (
          <input
            type="checkbox"
            className="rounded border-gray-300 text-brand-600 flex-shrink-0 cursor-pointer"
            checked={checkedIds.has(node.originalId)}
            onClick={(e) => e.stopPropagation()}
            onChange={(e) => onCheckChange(node.originalId, e.target.checked)}
          />
        )}

        <span className="flex-shrink-0 flex items-center leading-none">
          {hasChildren
            ? (isExpanded ? <IconFolderOpen /> : <IconFolderClosed />)
            : <IconFile />}
        </span>

        <a
          href={node.href}
          className={`
            text-sm font-medium flex-shrink-0 transition-colors
            ${isCurrent ? 'text-brand-700' : 'text-gray-900 hover:text-brand-700'}
          `}
          onClick={(e) => e.stopPropagation()}
        >
          {node.title}
        </a>

        {hasChildren && (
          <>
            <span className={`text-xs flex-shrink-0 font-mono transition-colors ${isExpanded ? 'text-gray-300' : 'text-gray-400'}`}>
              ({node.childrenCount})
            </span>
            <span className="flex-shrink-0 text-gray-400 group-hover:text-gray-600 transition-colors">
              {isExpanded ? <IconChevronDown /> : <IconChevronRight />}
            </span>
          </>
        )}

        {node.comment && (
          <>
            <span className="text-gray-300 flex-shrink-0 text-xs select-none">·</span>
            <span className="text-xs text-gray-400 italic truncate flex-1 min-w-0">
              {node.comment}
            </span>
          </>
        )}
      </div>

      {isExpanded && hasChildren && (
        <div className="relative ml-5">
          <div style={{ position: 'absolute', left: 5, top: 0, bottom: (noFade || depth >= 1) ? 12 : 0, width: 1, background: (noFade || depth >= 1) ? guideColor : `linear-gradient(to bottom, ${guideColor} 88%, transparent 100%)` }} />

          {node.children!.map((child, idx) => {
            const childIsLast = idx === node.children!.length - 1;
            return (
              <div key={child.key} className="relative pl-5">
                <div style={{ position: 'absolute', left: 5, top: 14, width: 14, height: 1, backgroundColor: guideColor }} />
                {(noFade || depth >= 1) && childIsLast && (
                  <div style={{ position: 'absolute', left: 5, top: 15, bottom: 0, width: 1, backgroundColor: 'white' }} />
                )}
                <GeistNode node={child} depth={depth + 1} isLast={childIsLast} {...shared} />
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
//  MAIN EXPORT
// ════════════════════════════════════════════════════════════════════

export default function DatasetTreeRcTree({
  treeNodes,
  projectNumber,
  selectedIds,
  onSelectionChange,
  searchQuery = '',
  currentDatasetId,
  variant = 'rctree',
  noFade = false,
}: DatasetTreeProps) {
  const hasCheckboxes = selectedIds !== undefined && onSelectionChange !== undefined;

  const roots = useMemo(
    () => buildRoots(treeNodes, projectNumber),
    [treeNodes, projectNumber],
  );

  const filteredRoots = useMemo(
    () => filterNodes(roots, searchQuery),
    [roots, searchQuery],
  );

  // ── rc-tree specific ──────────────────────────────────────────────
  const checkedKeys = useMemo(
    () => (selectedIds ? Array.from(selectedIds).map(String) : []),
    [selectedIds],
  );

  const handleRcCheck = (checked: Key[] | { checked: Key[]; halfChecked: Key[] }) => {
    if (!onSelectionChange) return;
    const keys = Array.isArray(checked) ? checked : checked.checked;
    onSelectionChange(new Set(keys.map((k) => Number(k))));
  };

  // ── expand state (Geist) ─────────────────────────────────────────
  const allKeys = useMemo(() => collectAllKeys(roots), [roots]);
  const initializedRef = useRef(false);
  const [expandedKeys, setExpandedKeys] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!initializedRef.current && allKeys.size > 0) {
      initializedRef.current = true;
      setExpandedKeys(new Set(allKeys));
    }
  }, [allKeys]);

  const prevSearchRef = useRef('');
  useEffect(() => {
    if (searchQuery.trim() && searchQuery !== prevSearchRef.current) {
      setExpandedKeys(new Set(allKeys));
    }
    prevSearchRef.current = searchQuery;
  }, [searchQuery, allKeys]);

  const toggleExpand = (key: string) => {
    setExpandedKeys((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key); else next.add(key);
      return next;
    });
  };

  const checkedIds = selectedIds ?? new Set<number>();

  const handleCheckChange = (id: number, checked: boolean) => {
    if (!onSelectionChange) return;
    const next = new Set(checkedIds);
    if (checked) next.add(id); else next.delete(id);
    onSelectionChange(next);
  };

  const sharedNodeProps: SharedNodeProps = {
    expandedKeys,
    toggleExpand,
    currentDatasetId,
    hasCheckboxes,
    checkedIds,
    onCheckChange: handleCheckChange,
    noFade,
  };

  if (!filteredRoots.length) {
    return <div className="text-gray-500 p-4 text-sm">No tree data available</div>;
  }

  // ── VARIANT: RC-TREE ─────────────────────────────────────────────
  if (variant === 'rctree') return (
    <div
      className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-auto p-3"
      style={{ maxHeight: 500 }}
    >
      <style>{`
        .rc-tree-icon__close,
        .rc-tree-icon__docu { background-position: -110px -16px !important; }
      `}</style>
      <Tree
        treeData={filteredRoots}
        defaultExpandAll
        checkable={hasCheckboxes}
        checkStrictly={hasCheckboxes}
        checkedKeys={hasCheckboxes ? checkedKeys : undefined}
        onCheck={hasCheckboxes ? handleRcCheck : undefined}
        selectable={false}
        showLine
        showIcon
        titleRender={(node: any) => {
          const isCurrent = currentDatasetId !== undefined && node.originalId === currentDatasetId;
          return (
            <span className="text-sm">
              {node.childrenCount > 0 && (
                <span className="text-xs text-gray-500 mr-1">({node.childrenCount})</span>
              )}
              <a
                href={node.href}
                className={`no-underline rounded px-1 hover:bg-brand-50 ${
                  isCurrent ? 'font-bold text-brand-700' : 'text-gray-900 hover:text-brand-700'
                }`}
                onClick={(e) => e.stopPropagation()}
              >
                {node.title}
              </a>
              {node.comment && (
                <span className="text-xs text-gray-400 italic ml-1">{node.comment}</span>
              )}
            </span>
          );
        }}
      />
    </div>
  );

  // ── VARIANT: GEIST ───────────────────────────────────────────────
  return (
    <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
      <div className="flex items-center justify-between px-4 py-2.5 border-b border-gray-100">
        <span className="text-xs font-medium text-gray-400 tracking-widest uppercase">Datasets</span>
        <span className="text-xs text-gray-300 font-mono">
          {filteredRoots.length} root{filteredRoots.length !== 1 ? 's' : ''}
        </span>
      </div>
      <div className="overflow-auto p-3" style={{ maxHeight: 520 }}>
        {filteredRoots.map((node, idx) => (
          <GeistNode
            key={node.key}
            node={node}
            depth={0}
            isLast={idx === filteredRoots.length - 1}
            {...sharedNodeProps}
          />
        ))}
      </div>
    </div>
  );
}
