import { DirectoryContents } from '../types/files';
import { httpClient } from './client';

export const filesApi = {
  // Browses gStore. The backend confines the listing to the caller's own
  // project directories, so an empty path lists exactly those.
  async getDirectoryContents(path: string): Promise<DirectoryContents> {
    const normalizedPath = path.replace(/^\/+|\/+$/g, '');
    const query = normalizedPath ? `?path=${encodeURIComponent(normalizedPath)}` : '';
    return httpClient.request<DirectoryContents>(`/api/v1/files${query}`);
  },

  getDownloadUrl(path: string): string {
    return `/api/files/download?path=${encodeURIComponent(path)}`;
  },
};
