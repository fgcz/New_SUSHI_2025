import { httpClient } from './client';
import { AuthenticationStatus, AuthenticationConfig, LoginResponse, TokenVerifyResponse } from '../types/auth';

export const authApi = {
  async login(login: string, password: string): Promise<LoginResponse> {
    const response = await httpClient.request<LoginResponse>('/api/v1/auth/login', {
      method: 'POST',
      body: JSON.stringify({ login, password }),
    });
    
    httpClient.setToken(response.token);
    return response;
  },

  async register(
    login: string, 
    email: string, 
    password: string, 
    password_confirmation: string
  ): Promise<LoginResponse> {
    const response = await httpClient.request<LoginResponse>('/api/v1/auth/register', {
      method: 'POST',
      body: JSON.stringify({ login, email, password, password_confirmation }),
    });
    
    httpClient.setToken(response.token);
    return response;
  },

  logout(): void {
    httpClient.clearToken();
  },

  async verifyToken(): Promise<TokenVerifyResponse> {
    return httpClient.request<TokenVerifyResponse>('/api/v1/auth/verify');
  },

  async getAuthenticationStatus(): Promise<AuthenticationStatus> {
    return httpClient.request<AuthenticationStatus>('/auth/login_options');
  },

  async getAuthenticationConfig(): Promise<AuthenticationConfig> {
    return httpClient.request<AuthenticationConfig>('/api/v1/authentication_config');
  },
};
