'use client';

import { useEffect, useMemo, useState } from 'react';
import type { TreeNode } from '@/lib/api';

interface DatasetTreeProps {
  treeNodes: TreeNode[];
  selectedIds: Set<number>;
  onSelectionChange: (selected: Set<number>) => void;
  projectNumber: number;
  searchQuery?: string;
}

interface TreeNodeData extends TreeNode {
  children: TreeNodeData[];
  expanded: boolean;
  visible: boolean;
}

export default function DatasetTree({
  treeNodes,
  selectedIds,
  onSelectionChange,
  projectNumber,
  searchQuery = ''
}: DatasetTreeProps) {
  const [roots, setRoots] = useState<TreeNodeData[]>([]);

  useEffect(() => {
    const map = new Map<number | string, TreeNodeData>();
    const localRoots: TreeNodeData[] = [];

    treeNodes.forEach((n) => {
      map.set(n.id, { ...n, children: [], expanded: false, visible: true });
    });

    treeNodes.forEach((n) => {
      const node = map.get(n.id)!;
      const parentKey = n.parent;
      if (parentKey === '#') {
        localRoots.push(node);
      } else {
        const p = map.get(parentKey);
        if (p) {
          p.children.push(node);
        } else {
          localRoots.push(node);
        }
      }
    });

    setRoots(localRoots);
  }, [treeNodes]);

  useEffect(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) {
      setRoots((prev) => {
        const reset = (nodes: TreeNodeData[]) => nodes.forEach((n) => {
          n.visible = true;
          reset(n.children);
        });
        const cp = structuredClone(prev);
        reset(cp);
        return cp;
      });
      return;
    }
    setRoots((prev) => {
      const cp = structuredClone(prev);
      const update = (nodes: TreeNodeData[]): boolean => {
        let anyVisible = false;
        nodes.forEach((n) => {
          const childVisible = update(n.children);
          const selfMatch = (n.dataset_data.name || '').toLowerCase().includes(q);
          n.visible = selfMatch || childVisible;
          if (n.visible && childVisible) n.expanded = true;
          anyVisible ||= n.visible;
        });
        return anyVisible;
      };
      update(cp);
      return cp;
    });
  }, [searchQuery]);

  const toggleExpanded = (id: number) => {
    setRoots((prev) => {
      const cp = structuredClone(prev);
      const walk = (nodes: TreeNodeData[]) => nodes.forEach((n) => {
        if (n.id === id) n.expanded = !n.expanded;
        walk(n.children);
      });
      walk(cp);
      return cp;
    });
  };

  const toggleSelected = (id: number) => {
    const next = new Set(selectedIds);
    if (next.has(id)) next.delete(id); else next.add(id);
    onSelectionChange(next);
  };

  const renderNode = (n: TreeNodeData, level: number) => {
    if (!n.visible) return null;
    const hasChildren = n.children.length > 0;
    const isSelected = selectedIds.has(n.id);
    return (
      <div key={n.id} className="select-none">
        <div className="flex items-center py-1 hover:bg-gray-100" style={{ paddingLeft: `${level * 16 + 8}px` }}>
          {hasChildren ? (
            <button onClick={() => toggleExpanded(n.id)} className="mr-1 w-4 h-4 flex items-center justify-center text-gray-600">
              {n.expanded ? '▼' : '▶'}
            </button>
          ) : (
            <span className="mr-1 w-4 h-4" />
          )}
          <input type="checkbox" className="mr-2" checked={isSelected} onChange={() => toggleSelected(n.id)} />
          <a href={n.a_attr.href} className="text-blue-600 hover:underline text-sm" dangerouslySetInnerHTML={{ __html: n.text }} />
        </div>
        {hasChildren && n.expanded && (
          <div>
            {n.children.map((c) => renderNode(c, level + 1))}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="border rounded p-3 bg-white">
      <div className="max-h-96 overflow-y-auto">
        {roots.map((r) => renderNode(r, 0))}
      </div>
    </div>
  );
}


