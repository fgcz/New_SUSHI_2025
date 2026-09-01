const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://fgcz-h-083.fgcz-net.unizh.ch:4000';

// An HTTP failure that still carries what the server SAID about it.
//
// Every failed request used to throw `API request failed: 403 Forbidden` and drop
// the response body on the floor — so a read-only node refusing a job submission
// with a precise explanation reached the user as "Please try again", advice that
// could never work. The status is kept separately so callers can branch on it
// without parsing prose.
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

// The backend reports failures as { error, message } (the Rack write-policy guard
// and every controller). Fall back to the status line when the body is empty or
// not JSON, e.g. a proxy error page.
async function describeFailure(response: Response): Promise<string> {
  try {
    const body = await response.clone().json();
    const detail = body?.message || body?.error || body?.errors?.join?.(', ');
    if (detail) return String(detail);
  } catch {
    // not JSON — fall through
  }
  return `Request failed: ${response.status} ${response.statusText}`;
}

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
      throw new ApiError(response.status, await describeFailure(response));
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

  // Fetches a non-JSON body (the TSV exports) and hands it to the browser as a
  // download. The server names the file in Content-Disposition; `fallbackName`
  // is only used when the header is absent.
  async download(endpoint: string, fallbackName: string): Promise<void> {
    const headers: Record<string, string> = {};
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const response = await fetch(`${this.baseUrl}${endpoint}`, { headers });
    if (!response.ok) {
      throw new ApiError(response.status, await describeFailure(response));
    }

    const disposition = response.headers.get('Content-Disposition') || '';
    const match = disposition.match(/filename="?([^"]+)"?/);
    const blob = await response.blob();

    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = match ? match[1] : fallbackName;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  buildQueryString(params: Record<string, any>): string {
    const search = new URLSearchParams();
    Object.entries(params).forEach(([key, value]) => {
      // Exclude undefined, null, and empty strings
      if (value !== undefined && value !== null && value !== '') {
        search.set(key, String(value));
      }
    });
    return search.toString();
  }
}

export const httpClient = new HttpClient();
