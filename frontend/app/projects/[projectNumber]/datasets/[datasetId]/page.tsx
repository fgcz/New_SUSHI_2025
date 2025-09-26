'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';
import { projectApi, datasetApi } from '@/lib/api';
import { RunnableApp, FolderTreeNode } from '@/lib/types';
import 'jstree/dist/themes/default/style.min.css';

export default function DatasetDetailPage() {
  const params = useParams<{ projectNumber: string; datasetId: string }>();
  const projectNumber = Number(params.projectNumber);
  const datasetId = Number(params.datasetId);
  const treeRef = useRef<HTMLDivElement>(null);

  const { data, isLoading, error } = useQuery({
    queryKey: ['datasets', projectNumber],
    queryFn: () => projectApi.getProjectDatasets(projectNumber),
    staleTime: 60_000,
  });

  const { data: runnableApps, isLoading: runnableAppsLoading, error: runnableAppsError } = useQuery({
    queryKey: ['runnableApps', datasetId],
    queryFn: () => datasetApi.getRunnableApps(datasetId),
    staleTime: 60_000,
  });

  const { data: folderTree, isLoading: folderTreeLoading, error: folderTreeError } = useQuery({
    queryKey: ['folderTree', datasetId],
    queryFn: () => datasetApi.getFolderTree(datasetId),
    staleTime: 60_000,
  });

  useEffect(() => {
    if (folderTree && treeRef.current) {
      // Dynamically import jQuery and jsTree
      import('jquery').then((jqueryModule) => {
        const $ = jqueryModule.default;
        
        // Assign jQuery to global window object
        (window as any).$ = $;
        (window as any).jQuery = $;
        
        import('jstree').then(() => {
          // Clear any existing tree
          $(treeRef.current).jstree('destroy');
          
          // Transform the data for jsTree format
          const treeData = folderTree.map((node: FolderTreeNode) => {
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

          // Initialize jsTree with proper configuration
          $(treeRef.current).jstree({
            'core': {
              'data': treeData,
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
            'html_data': {
              'data': treeData
            },
            'plugins': ['state', 'types'],
            'types': {
              'default': {
                'icon': 'jstree-folder'
              },
              'file': {
                'icon': 'jstree-file'
              }
            },
            'state': {
              'key': 'dataset-folder-tree'
            }
          }).on('ready.jstree', function () {
            // Expand all nodes by default
            $(this).jstree('open_all');
          }).on('select_node.jstree', function (e: any, data: any) {
            // Handle node selection
            const nodeData = data.node.data;
            if (nodeData) {
              const nodeType = nodeData.isCurrentDataset ? ' (Current Dataset)' : '';
              const comment = nodeData.comment || 'No description';
              console.log('Selected:', data.node.text, '-', comment + nodeType);
            }
          });
        });
      });
    }

    // Cleanup function
    return () => {
      if (treeRef.current) {
        import('jquery').then((jqueryModule) => {
          const $ = jqueryModule.default;
          if ($(treeRef.current).jstree) {
            $(treeRef.current).jstree('destroy');
          }
        });
      }
    };
  }, [folderTree]);

  const handleAppClick = (category: string, app: string) => {
    console.log(`Running ${app} from ${category} category for dataset ${datasetId}`);
  };

  if (isLoading) return <div className="container mx-auto px-6 py-8">Loading dataset...</div>;
  if (error) return <div className="container mx-auto px-6 py-8 text-red-600">Failed to load dataset</div>;

  const dataset = data?.datasets?.find(ds => ds.id === datasetId);

  if (!dataset) {
    return (
      <div className="container mx-auto px-6 py-8">
        <h1 className="text-2xl font-bold mb-4 text-red-600">Dataset Not Found</h1>
        <p className="text-gray-700 mb-6">Dataset {datasetId} was not found in project {projectNumber}.</p>
        <Link href={`/projects/${projectNumber}/datasets`} className="text-blue-600 hover:underline">← Back to Datasets</Link>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-6 py-8">
      <div className="mb-6">
        <Link href={`/projects/${projectNumber}/datasets`} className="text-blue-600 hover:underline">← Back to Datasets</Link>
      </div>

      <h1 className="text-2xl font-bold mb-6">Dataset Details - {dataset.name}</h1>

      <div className="bg-white border rounded-lg overflow-hidden">
        <div className="p-6 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <h3 className="text-lg font-semibold mb-4">Basic Information</h3>
              <div className="space-y-3">
                <div className="flex justify-between">
                  <span className="font-medium text-gray-600">ID:</span>
                  <span>{dataset.id}</span>
                </div>
                <div className="flex justify-between">
                  <span className="font-medium text-gray-600">Name:</span>
                  <span>{dataset.name}</span>
                </div>
                <div className="flex justify-between">
                  <span className="font-medium text-gray-600">Project:</span>
                  <span>{dataset.project_number}</span>
                </div>
                <div className="flex justify-between">
                  <span className="font-medium text-gray-600">Created:</span>
                  <span>{new Date(dataset.created_at).toLocaleString()}</span>
                </div>
                <div className="flex justify-between">
                  <span className="font-medium text-gray-600">Created by:</span>
                  <span>{dataset.user_login || 'N/A'}</span>
                </div>
              </div>
            </div>

            <div>
              <h3 className="text-lg font-semibold mb-4">Application & Samples</h3>
              <div className="space-y-3">
                <div className="flex justify-between">
                  <span className="font-medium text-gray-600">SushiApp:</span>
                  <span>{dataset.sushi_app_name || 'N/A'}</span>
                </div>
                <div className="flex justify-between">
                  <span className="font-medium text-gray-600">Samples:</span>
                  <span>{dataset.completed_samples ?? 0} / {dataset.samples_length ?? 0}</span>
                </div>
                <div className="flex justify-between">
                  <span className="font-medium text-gray-600">BFabric ID:</span>
                  <span>
                    {dataset.bfabric_id ? (
                      <a
                        href={`https://fgcz-bfabric.uzh.ch/bfabric/dataset/show.html?id=${dataset.bfabric_id}&tab=details`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-blue-600 hover:underline"
                      >
                        {dataset.bfabric_id}
                      </a>
                    ) : 'N/A'}
                  </span>
                </div>
              </div>
            </div>
          </div>

          {(dataset.parent_id || (dataset.children_ids && dataset.children_ids.length > 0)) && (
            <div className="mt-8 pt-6 border-t">
              <h3 className="text-lg font-semibold mb-4">Relationships</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {dataset.parent_id && (
                  <div>
                    <span className="font-medium text-gray-600">Parent Dataset:</span>
                    <div className="mt-2">
                      <Link
                        href={`/projects/${projectNumber}/datasets/${dataset.parent_id}`}
                        className="text-blue-600 hover:underline"
                      >
                        Dataset {dataset.parent_id}
                      </Link>
                    </div>
                  </div>
                )}
                
                {dataset.children_ids && dataset.children_ids.length > 0 && (
                  <div>
                    <span className="font-medium text-gray-600">Child Datasets:</span>
                    <div className="mt-2 space-y-1">
                      {dataset.children_ids.map((childId) => (
                        <div key={childId}>
                          <Link
                            href={`/projects/${projectNumber}/datasets/${childId}`}
                            className="text-blue-600 hover:underline"
                          >
                            Dataset {childId}
                          </Link>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}

          <div className="mt-8 pt-6 border-t">
            <h3 className="text-lg font-semibold mb-4">Folder Structure</h3>
            {folderTreeLoading ? (
              <div>Loading folder tree...</div>
            ) : folderTreeError ? (
              <div className="text-red-600">Failed to load folder tree</div>
            ) : (
              <div ref={treeRef} className="folder-tree-container"></div>
            )}
          </div>

          {runnableApps && runnableApps.length > 0 && (
            <div className="mt-8 pt-6 border-t">
              <h3 className="text-lg font-semibold mb-4">Runnable Applications</h3>
              {runnableAppsLoading ? (
                <div>Loading runnable apps...</div>
              ) : runnableAppsError ? (
                <div className="text-red-600">Failed to load runnable apps</div>
              ) : (
                <div className="space-y-6">
                  {runnableApps.map((category: RunnableApp, index: number) => (
                    <div key={index} className="bg-gray-50 rounded-lg p-4">
                      <h4 className="text-md font-medium mb-3 text-gray-800 capitalize">
                        {category.category}
                      </h4>
                      <div className="flex flex-wrap gap-2">
                        {category.applications.map((app: string) => (
                          <button
                            key={app}
                            onClick={() => handleAppClick(category.category, app)}
                            className="px-3 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors duration-200 text-sm font-medium"
                          >
                            {app}
                          </button>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}


