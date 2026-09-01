import { describe, it, expect, beforeEach } from 'vitest';
import { http, HttpResponse } from 'msw';
import { server } from '@/mocks/server';
import { authApi } from './auth';
import { httpClient } from './client';

// The response body below is the backend's REAL contract
// (Api::V1::AuthController#token_response): { access_token, token_type, user }.
// It is written out literally rather than built from a helper, because the bug this
// pins was exactly a client reading a field name the server never sends — a shared
// fixture would have carried the same mistake into the test.
const BACKEND_TOKEN_RESPONSE = {
  access_token: 'eyJhbGciOiJIUzI1NiJ9.header.signature',
  token_type: 'bearer',
  user: { user_id: 1, login: 'masaomi', projects: [1001, 35611] },
};

describe('authApi.login', () => {
  beforeEach(() => {
    httpClient.clearToken();
  });

  it('stores the access_token the backend actually sends', async () => {
    server.use(
      http.post('*/api/v1/auth/login', () => HttpResponse.json(BACKEND_TOKEN_RESPONSE))
    );

    const result = await authApi.login('masaomi', 'secret');

    expect(result.access_token).toBe(BACKEND_TOKEN_RESPONSE.access_token);
    expect(localStorage.getItem('jwt_token')).toBe(BACKEND_TOKEN_RESPONSE.access_token);
  });

  it('sends the stored token as a bearer on the next request', async () => {
    server.use(
      http.post('*/api/v1/auth/login', () => HttpResponse.json(BACKEND_TOKEN_RESPONSE)),
      http.get('*/api/v1/auth/verify', ({ request }) =>
        HttpResponse.json({ valid: true, authorization: request.headers.get('Authorization') })
      )
    );

    await authApi.login('masaomi', 'secret');
    const verified = (await authApi.verifyToken()) as unknown as { authorization: string };

    expect(verified.authorization).toBe(`Bearer ${BACKEND_TOKEN_RESPONSE.access_token}`);
  });
});
