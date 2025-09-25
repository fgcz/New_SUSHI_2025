import { projectApi } from './api';

describe('Project API', () => {
  beforeEach(() => {
    (global.fetch as jest.Mock).mockReset();
  });

  it('builds URL with query params for getProjectDatasets', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => ({ ok: true }) });
    await projectApi.getProjectDatasets(1001, { q: 'abc', page: 2, per: 25 });
    const url = (global.fetch as jest.Mock).mock.calls[0][0] as string;
    expect(url).toMatch(/\/api\/v1\/projects\/1001\/datasets\?q=abc&page=2&per=25$/);
  });

  it('calls /api/v1/projects for getUserProjects', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => ({ projects: [], current_user: 'anon' }) });
    await projectApi.getUserProjects();
    const url = (global.fetch as jest.Mock).mock.calls[0][0] as string;
    expect(url).toMatch(/\/api\/v1\/projects$/);
  });

  it('throws on non-ok response', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({ ok: false, status: 500, statusText: 'Server Error' });
    await expect(projectApi.getUserProjects()).rejects.toThrow('API request failed: 500 Server Error');
  });
});


