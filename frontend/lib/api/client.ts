const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://fgcz-h-083.fgcz-net.unizh.ch:4000';

export class HttpClient {
  private baseUrl: string;
  private token: string | null = null;

  constructor(baseUrl: string = API_BASE_URL) {
    this.baseUrl = baseUrl;
    if (typeof window !== 'undefined') {
      this.token = localStorage.getItem('jwt_token');
    }
  }

  async request<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
    const url = `${this.baseUrl}${endpoint}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };

    if (options.headers) {
      Object.entries(options.headers).forEach(([key, value]) => {
        if (typeof value === 'string') {
          headers[key] = value;
        }
      });
    }
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

  setToken(token: string): void {
    this.token = token;
    if (typeof window !== 'undefined') {
      localStorage.setItem('jwt_token', token);
    }
  }

  clearToken(): void {
    this.token = null;
    if (typeof window !== 'undefined') {
      localStorage.removeItem('jwt_token');
    }
  }

  buildQueryString(params: Record<string, any>): string {
    const search = new URLSearchParams();
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        search.set(key, String(value));
      }
    });
    return search.toString();
  }
}

export const httpClient = new HttpClient();
