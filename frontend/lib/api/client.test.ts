import { describe, it, expect, beforeEach } from 'vitest';
import { http, HttpResponse } from 'msw';
import { server } from '@/mocks/server';
import { HttpClient, ApiError } from './client';

// The client used to throw `API request failed: 403 Forbidden` for every failure,
// discarding the body — so the backend's precise reason never reached the screen.
// The user meeting it saw "Please try again" against a permanent refusal.
describe('HttpClient error reporting', () => {
  let client: HttpClient;

  beforeEach(() => {
    client = new HttpClient('http://backend.test');
  });

  it("carries the server's explanation, not just the status line", async () => {
    server.use(
      http.post('*/api/v1/jobs', () =>
        HttpResponse.json(
          {
            error: 'read_only',
            message: "This SUSHI backend write policy is 'read_only'; POST /api/v1/jobs is not permitted.",
          },
          { status: 403 },
        ),
      ),
    );

    await expect(client.request('/api/v1/jobs', { method: 'POST' })).rejects.toThrow(
      /write policy is 'read_only'/,
    );
  });

  it('exposes the status so callers can branch without parsing prose', async () => {
    server.use(
      http.get('*/api/v1/datasets/1', () =>
        HttpResponse.json({ error: 'Forbidden' }, { status: 403 }),
      ),
    );

    await expect(client.request('/api/v1/datasets/1')).rejects.toMatchObject({
      status: 403,
      message: 'Forbidden',
    });
  });

  it('falls back to the status line when the body is not JSON', async () => {
    server.use(
      http.get('*/api/v1/datasets/2', () =>
        HttpResponse.text('<html>502 from a proxy</html>', { status: 502 }),
      ),
    );

    await expect(client.request('/api/v1/datasets/2')).rejects.toThrow(/502/);
  });

  it('throws ApiError, so the status survives the throw', async () => {
    server.use(
      http.get('*/api/v1/datasets/3', () => HttpResponse.json({}, { status: 404 })),
    );

    await expect(client.request('/api/v1/datasets/3')).rejects.toBeInstanceOf(ApiError);
  });
});
