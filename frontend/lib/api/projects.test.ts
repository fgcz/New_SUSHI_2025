import { projectApi } from './projects';
import { server } from '../../mocks/server';
import { http, HttpResponse } from 'msw';

describe('projectApi', () => {
  describe('getUserProjects', () => {
    it('calls correct endpoint', async () => {
      const result = await projectApi.getUserProjects();
      
      expect(result).toEqual({
        projects: expect.any(Array),
        current_user: expect.any(String)
      });
    });

    it('handles API errors correctly', async () => {
      // Override MSW handler to return error
      server.use(
        http.get('/api/v1/projects', () => {
          return new HttpResponse(null, { status: 500, statusText: 'Internal Server Error' });
        })
      );

      await expect(projectApi.getUserProjects()).rejects.toThrow(
        'API request failed: 500 Internal Server Error'
      );
    });
  });

  describe('getProjectDatasets', () => {
    it('builds URL with no parameters', async () => {
      const result = await projectApi.getProjectDatasets(1001);
      
      expect(result).toEqual({
        datasets: expect.any(Array),
        total_count: expect.any(Number),
        page: expect.any(Number),
        per: expect.any(Number),
        project_number: 1001
      });
    });

    it('builds URL with datasetName parameter', async () => {
      let interceptedUrl: string = '';
      
      server.use(
        http.get('/api/v1/projects/:projectId/datasets', ({ request }) => {
          interceptedUrl = request.url;
          return HttpResponse.json({
            datasets: [],
            total_count: 0,
            page: 1,
            per: 50,
            project_number: 1001
          });
        })
      );

      await projectApi.getProjectDatasets(1001, { datasetName: 'RNA-seq' });
      
      expect(interceptedUrl).toContain('datasetName=RNA-seq');
    });

    it('builds URL with user parameter', async () => {
      let interceptedUrl: string = '';
      
      server.use(
        http.get('/api/v1/projects/:projectId/datasets', ({ request }) => {
          interceptedUrl = request.url;
          return HttpResponse.json({
            datasets: [],
            total_count: 0,
            page: 1,
            per: 50,
            project_number: 1001
          });
        })
      );

      await projectApi.getProjectDatasets(1001, { user: 'alice' });
      
      expect(interceptedUrl).toContain('user=alice');
    });

    it('builds URL with multiple parameters', async () => {
      let interceptedUrl: string = '';
      
      server.use(
        http.get('/api/v1/projects/:projectId/datasets', ({ request }) => {
          interceptedUrl = request.url;
          return HttpResponse.json({
            datasets: [],
            total_count: 0,
            page: 1,
            per: 50,
            project_number: 1001
          });
        })
      );

      await projectApi.getProjectDatasets(1001, { 
        datasetName: 'RNA',
        user: 'alice',
        page: 2,
        per: 25
      });
      
      expect(interceptedUrl).toContain('datasetName=RNA');
      expect(interceptedUrl).toContain('user=alice');
      expect(interceptedUrl).toContain('page=2');
      expect(interceptedUrl).toContain('per=25');
    });

    it('handles empty/undefined parameters correctly', async () => {
      let interceptedUrl: string = '';
      
      server.use(
        http.get('/api/v1/projects/:projectId/datasets', ({ request }) => {
          interceptedUrl = request.url;
          return HttpResponse.json({
            datasets: [],
            total_count: 0,
            page: 1,
            per: 50,
            project_number: 1001
          });
        })
      );

      await projectApi.getProjectDatasets(1001, { 
        datasetName: '',
        user: undefined,
        page: 1
      });
      
      // Should not include empty or undefined parameters
      expect(interceptedUrl).not.toContain('datasetName=');
      expect(interceptedUrl).not.toContain('user=');
      expect(interceptedUrl).toContain('page=1');
    });

    it('handles 404 errors', async () => {
      server.use(
        http.get('/api/v1/projects/:projectId/datasets', () => {
          return new HttpResponse(null, { status: 404, statusText: 'Not Found' });
        })
      );

      await expect(projectApi.getProjectDatasets(9999)).rejects.toThrow(
        'API request failed: 404 Not Found'
      );
    });

    it('includes correct project number in endpoint', async () => {
      let interceptedUrl: string = '';
      
      server.use(
        http.get('/api/v1/projects/:projectId/datasets', ({ request, params }) => {
          interceptedUrl = request.url;
          expect(params.projectId).toBe('1001');
          return HttpResponse.json({
            datasets: [],
            total_count: 0,
            page: 1,
            per: 50,
            project_number: 1001
          });
        })
      );

      await projectApi.getProjectDatasets(1001);
      
      expect(interceptedUrl).toContain('/api/v1/projects/1001/datasets');
    });
  });
});