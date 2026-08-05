import { httpClient } from './client';
import { DirectoryContents } from '../types/files';

interface DirectoryContentsResponse {
  path: string;
  parent_path: string | null;
  pagination: { total: number; page: number; per_page: number; total_pages: number };
  items: Array<{
    name: string;
    type: 'file' | 'directory';
    modified: string;
    size: string;
    size_bytes: number | null;
  }>;
}

export const filesApi = {
  async getDirectoryContents(path: string, page = 1, perPage = 50): Promise<DirectoryContents> {
    const normalizedPath = path.replace(/^\/+|\/+$/g, '');
    const response = await httpClient.request<DirectoryContentsResponse>(
      `/files/${normalizedPath}?page=${page}&per_page=${perPage}`
    );

    return {
      currentPath: response.path,
      parentPath: response.parent_path,
      totalItems: response.pagination.total,
      items: response.items.map(item => ({
        name: item.name,
        type: item.type === 'directory' ? 'folder' : 'file',
        lastModified: item.modified,
        size: item.size_bytes,
      })),
    };
  },

  getDownloadUrl(path: string): string {
    const normalizedPath = path.replace(/^\/+|\/+$/g, '');
    return `/files/${normalizedPath}`;
  },
};
