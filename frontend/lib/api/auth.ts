import { httpClient } from './client';
import { AuthenticationStatus, AuthenticationConfig, LoginResponse, TokenVerifyResponse } from '../types/auth';

export const authApi = {
  async login(username: string, password: string): Promise<LoginResponse> {
    const response = await httpClient.request<LoginResponse>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    });

    // Store access token from response
    if (response.access_token) {
      httpClient.setToken(response.access_token);
    }
    return response;
  },

  async logout(): Promise<void> {
    try {
      // Call backend to revoke refresh token
      await httpClient.request('/auth/logout', {
        method: 'POST',
      });
    } catch {
      // Ignore errors - still clear local token
    }
    httpClient.clearToken();
  },

  async verifyToken(): Promise<TokenVerifyResponse> {
    return httpClient.request<TokenVerifyResponse>('/auth/me');
  },

  async getAuthenticationStatus(): Promise<AuthenticationStatus> {
    return httpClient.request<AuthenticationStatus>('/auth/login_options');
  },

  async refreshToken(): Promise<{ access_token: string }> {
    const response = await httpClient.request<{ access_token: string }>('/auth/refresh', {
      method: 'POST',
    });
    if (response.access_token) {
      httpClient.setToken(response.access_token);
    }
    return response;
  },
};
