// API client for authentication and app data

export interface AuthenticationStatus {
  standard_login: boolean;
  oauth2_login: boolean;
  two_factor_auth: boolean;
  ldap_auth: boolean;
  wallet_auth: boolean;
  enabled_methods: string[];
  authentication_skipped: boolean;
  current_user?: string;
}

export interface AuthenticationConfig {
  standard_login: {
    enabled: boolean;
    allow_registration: boolean;
    allow_password_reset: boolean;
  };
  oauth2_login: {
    enabled: boolean;
    providers: {
      google: boolean;
      github: boolean;
    };
  };
  two_factor_auth: {
    enabled: boolean;
    require_setup: boolean;
    backup_codes: boolean;
  };
  ldap_auth: {
    enabled: boolean;
    allow_registration: boolean;
    allow_password_reset: boolean;
    auto_create_user: boolean;
  };
  wallet_auth: {
    enabled: boolean;
    network: string;
    require_signature: boolean;
  };
}

export interface LoginResponse {
  token: string;
  user: {
    id: number;
    login: string;
    email: string;
  };
  message: string;
}

export interface Dataset {
  id: number;
  name: string;
  created_at: string;
  user: string;
}

export interface Project { number: number }
export interface UserProjectsResponse { projects: Project[]; current_user: string }
export interface ProjectDatasetsResponse {
  datasets: Array<{
    id: number;
    name: string;
    sushi_app_name?: string;
    completed_samples?: number;
    samples_length?: number;
    parent_id?: number | null;
    children_ids?: number[];
    user_login?: string | null;
    created_at: string;
    bfabric_id?: number | null;
    project_number: number;
  }>;
  total_count: number;
  page: number;
  per: number;
  project_number: number;
}

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://fgcz-h-037.fgcz-net.unizh.ch:4000';

class ApiClient {
  private baseUrl: string;
  private token: string | null = null;

  constructor(baseUrl: string = API_BASE_URL) {
    this.baseUrl = baseUrl;
    // Get token from browser localStorage
    if (typeof window !== 'undefined') {
      this.token = localStorage.getItem('jwt_token');
    }
  }

  private async request<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
    const url = `${this.baseUrl}${endpoint}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };

    // Add existing headers
    if (options.headers) {
      Object.entries(options.headers).forEach(([key, value]) => {
        if (typeof value === 'string') {
          headers[key] = value;
        }
      });
    }

    // Add JWT token to Authorization header if available
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const response = await fetch(url, {
      ...options,
      headers,
    });

    if (!response.ok) {
      throw new Error(`API request failed: ${response.status} ${response.statusText}`);
    }

    return response.json();
  }

  // Public API - JWT authentication (supports both standard and LDAP)
  async login(login: string, password: string): Promise<LoginResponse> {
    const response = await this.request<LoginResponse>('/api/v1/auth/login', {
      method: 'POST',
      body: JSON.stringify({ login, password }),
    });
    
    // Save token
    this.token = response.token;
    if (typeof window !== 'undefined') {
      localStorage.setItem('jwt_token', response.token);
    }
    
    return response;
  }

  // Public API - User registration (no authentication required)
  async register(login: string, email: string, password: string, password_confirmation: string): Promise<LoginResponse> {
    const response = await this.request<LoginResponse>('/api/v1/auth/register', {
      method: 'POST',
      body: JSON.stringify({ login, email, password, password_confirmation }),
    });
    
    // Save token
    this.token = response.token;
    if (typeof window !== 'undefined') {
      localStorage.setItem('jwt_token', response.token);
    }
    
    return response;
  }

  // Public API - Logout (no authentication required)
  logout(): void {
    this.token = null;
    if (typeof window !== 'undefined') {
      localStorage.removeItem('jwt_token');
    }
  }

  // Public API - Verify JWT token (no authentication required)
  async verifyToken(): Promise<{ user: any; valid: boolean }> {
    return this.request<{ user: any; valid: boolean }>('/api/v1/auth/verify');
  }

  // Public API - Get authentication status (no authentication required)
  async getAuthenticationStatus(): Promise<AuthenticationStatus> {
    return this.request<AuthenticationStatus>('/auth/login_options');
  }

  // Private API - Get authentication configuration (JWT authentication required)
  async getAuthenticationConfig(): Promise<AuthenticationConfig> {
    return this.request<AuthenticationConfig>('/api/v1/authentication_config');
  }

  // Private API - Dataset related (JWT authentication required)
  async getDatasets(): Promise<{ datasets: Dataset[]; total_count: number; current_user: string }> {
    return this.request<{ datasets: Dataset[]; total_count: number; current_user: string }>('/api/v1/datasets');
  }

  async getDataset(id: number): Promise<{ dataset: Dataset }> {
    return this.request<{ dataset: Dataset }>(`/api/v1/datasets/${id}`);
  }

  async createDataset(name: string): Promise<{ dataset: Dataset; message: string }> {
    return this.request<{ dataset: Dataset; message: string }>('/api/v1/datasets', {
      method: 'POST',
      body: JSON.stringify({ dataset: { name } }),
    });
  }

  // Public API - Hello endpoint (no authentication required)
  async getHello(): Promise<{ message: string }> {
    return this.request<{ message: string }>('/api/v1/hello');
  }

  // New APIs
  async getUserProjects(): Promise<UserProjectsResponse> {
    return this.request<UserProjectsResponse>('/api/v1/projects');
  }

  async getProjectDatasets(projectNumber: number, params: { q?: string; page?: number; per?: number } = {}): Promise<ProjectDatasetsResponse> {
    const search = new URLSearchParams();
    if (params.q) search.set('q', params.q);
    if (params.page) search.set('page', String(params.page));
    if (params.per) search.set('per', String(params.per));
    const qs = search.toString();
    const endpoint = `/api/v1/projects/${projectNumber}/datasets${qs ? `?${qs}` : ''}`;
    return this.request<ProjectDatasetsResponse>(endpoint);
  }
}

export const apiClient = new ApiClient(); 