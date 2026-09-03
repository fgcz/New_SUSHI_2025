import { httpClient } from './client';
import {
  AuthenticationStatus,
  AuthenticationConfig,
  LoginResponse,
  TokenVerifyResponse,
  BfabricDeviceStart,
  BfabricDevicePoll,
} from '../types/auth';

export const authApi = {
  async login(login: string, password: string): Promise<LoginResponse> {
    const response = await httpClient.request<LoginResponse>('/api/v1/auth/login', {
      method: 'POST',
      body: JSON.stringify({ login, password }),
    });

    httpClient.setToken(response.access_token);
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

    httpClient.setToken(response.access_token);
    return response;
  },

  // ----- B-Fabric OIDC, browser side -------------------------------------
  //
  // The backend runs the device flow; this page only shows the code and waits. The
  // browser never touches a B-Fabric token: that credential is LIMS-wide, while the SUSHI
  // session it buys is not, so keeping it out of the page turns one XSS from a
  // whole-LIMS compromise into a thirty-minute one.

  async startBfabricDeviceLogin(write: boolean): Promise<BfabricDeviceStart> {
    return httpClient.request<BfabricDeviceStart>(
      `/api/v1/auth/bfabric/device/start${write ? '?write=1' : ''}`,
    );
  },

  // Resolves with {status:'pending'} while waiting. A terminal failure (expired, refused,
  // B-Fabric unreachable) arrives as a thrown ApiError carrying the server's own message.
  async pollBfabricDeviceLogin(handle: string): Promise<BfabricDevicePoll> {
    const result = await httpClient.request<BfabricDevicePoll>(
      `/api/v1/auth/bfabric/device/poll?handle=${encodeURIComponent(handle)}`,
    );

    // Assert before storing. This codebase has already shipped `undefined` as a bearer
    // once, because the server said `access_token` and the client read `.token`; a
    // successful login then reported "Login failed".
    if (result.status === 'ok') {
      if (typeof result.access_token !== 'string' || result.access_token.length === 0) {
        throw new Error('The backend reported a successful sign-in but returned no token.');
      }
      httpClient.setToken(result.access_token);
    }
    return result;
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
