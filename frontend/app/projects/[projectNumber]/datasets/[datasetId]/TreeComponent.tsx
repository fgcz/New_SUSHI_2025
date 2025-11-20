'use client';

import { useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { DatasetTreeNode } from '@/lib/types/dataset';
import $ from 'jquery';
import 'jstree';
import 'jstree/dist/themes/default/style.min.css';

// Type extension for jstree
declare global {
  interface JQuery {
    jstree(options?: any): any;
  }
}

interface TreeComponentProps {
  datasetTree: DatasetTreeNode[];
  datasetId: number;
  projectNumber: number;
}

export default function TreeComponent({ datasetTree, datasetId, projectNumber }: TreeComponentProps) {
  const treeRef = useRef<HTMLDivElement>(null);
  const router = useRouter();

  useEffect(() => {
    if (!datasetTree || !treeRef.current) return;

    // Clear any existing tree safely
    try {
      if ($(treeRef.current).jstree(true)) {
        $(treeRef.current).jstree('destroy');
      }
    } catch (e) {
      // Ignore destroy errors during re-initialization
    }
    
    // Transform the data for jsTree format
    const treeData = datasetTree.map((node: DatasetTreeNode) => {
      const isCurrentDataset = node.id === datasetId;
      const nodeAttrs: any = {};
      
      if (isCurrentDataset) {
        nodeAttrs.style = "font-weight: bold; color: #2563eb;";
      }
      
      const commentText = node.comment && node.comment.trim() 
        ? ` <small><font color="gray">${node.comment}</font></small>` 
        : '';
      
      const nodeText = isCurrentDataset 
        ? `<strong>${node.name}</strong>${commentText}`
        : `${node.name}${commentText}`;
      
      return {
        id: node.id.toString(),
        text: nodeText,
        parent: node.parent === "#" ? "#" : node.parent.toString(),
        data: {
          comment: node.comment || '',
          isCurrentDataset
        },
        icon: "jstree-folder",
        a_attr: nodeAttrs
      };
    });

    // Small delay to ensure DOM is fully ready
    setTimeout(() => {
      if (!treeRef.current) return;
      
      const $tree = $(treeRef.current);
      
      // Initialize jsTree with proper configuration
      $tree.jstree({
        'core': {
          'data': treeData,
          'worker': false, // Disable jsTree workers to prevent window errors
          'themes': {
            'name': 'default',
            'responsive': true,
            'variant': 'small',
            'stripes': false,
            'dots': true
          },
          'multiple': false,
          'animation': 200,
          'check_callback': true
        },
        'plugins': ['types'],
        'types': {
          'default': {
            'icon': 'jstree-folder'
          }
        }
      });

      // Bind events after initialization
      $tree.on('ready.jstree', function () {
        // Expand all nodes by default
        $(this).jstree('open_all');
      });

      $tree.on('select_node.jstree', function (e: any, data: any) {
        // Handle node selection
        const nodeData = data.node.data;
        const nodeId = parseInt(data.node.id);
        
        if (nodeData) {
          // Navigate to the dataset page using the node ID
          router.push(`/projects/${projectNumber}/datasets/${nodeId}`);
        }
      });
    }, 50); // Increased delay to ensure DOM stability

    // Cleanup function
    return () => {
      if (treeRef.current) {
        try {
          if ($(treeRef.current).jstree(true)) {
            $(treeRef.current).jstree('destroy');
          }
        } catch (e) {
          // Ignore cleanup errors
        }
      }
    };
  }, [datasetTree, datasetId, projectNumber]);

  return <div ref={treeRef} className="folder-tree-container"></div>;
}
