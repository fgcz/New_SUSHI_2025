import { httpClient } from './client';
import { DirectoryContents } from '../types/files';

// Backend response type (snake_case)
interface DirectoryContentsResponse {
  current_path: string;
  parent_path: string | null;
  total_items: number;
  items: Array<{
    name: string;
    type: 'file' | 'folder';
    last_modified: string;
    size: number | null;
  }>;
}

export const filesApi = {
  async getDirectoryContents(path: string): Promise<DirectoryContents> {
    // Normalize path (remove leading/trailing slashes)
    const normalizedPath = path.replace(/^\/+|\/+$/g, '');

    const response = await httpClient.request<DirectoryContentsResponse>(
      `/files/?path=${encodeURIComponent(normalizedPath)}`
    );

    // Transform snake_case response to camelCase for frontend
    return {
      currentPath: response.current_path,
      parentPath: response.parent_path,
      totalItems: response.total_items,
      items: response.items.map(item => ({
        name: item.name,
        type: item.type,
        lastModified: item.last_modified,
        size: item.size,
      })),
    };
  },

  getDownloadUrl(path: string): string {
    return `/files/download?path=${encodeURIComponent(path)}`;
  },
};
