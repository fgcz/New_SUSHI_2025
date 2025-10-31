import { httpClient } from './client';
import { HelloResponse } from '../types/misc';

export const miscApi = {
  async getHello(): Promise<HelloResponse> {
    return httpClient.request<HelloResponse>('/api/v1/hello');
  },
};