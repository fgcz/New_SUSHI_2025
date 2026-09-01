import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import Home from './page';

// Reported from a browser on the production node: the top page sat on
// "Redirecting to project..." and the login screen never appeared, because this
// component navigated from a bare mount effect while AuthContext was still
// deciding whether to send the visitor to /login.

const replace = vi.fn();

vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace, push: vi.fn() }),
}));

let authStatus: { authentication_skipped: boolean; current_user?: string } | null = null;
let authLoading = false;
let projects: { number: number }[] = [{ number: 1001 }];
let projectsLoading = false;

vi.mock('@/providers/AuthContext', () => ({
  useAuth: () => ({ authStatus, loading: authLoading, error: null }),
}));

vi.mock('@/lib/hooks', () => ({
  useProjectList: () => ({
    userProjects: { projects },
    isLoading: projectsLoading,
    error: null,
    isEmpty: projects.length === 0,
    refetch: vi.fn(),
  }),
}));

describe('Home (landing page)', () => {
  beforeEach(() => {
    replace.mockClear();
    authStatus = null;
    authLoading = false;
    projects = [{ number: 1001 }];
    projectsLoading = false;
  });

  it('does not navigate while authentication is still being checked', () => {
    authLoading = true;
    render(<Home />);

    expect(replace).not.toHaveBeenCalled();
  });

  // THE REPORTED BUG. Navigating here raced AuthContext's push to /login, so the
  // login screen never got a chance to render.
  it('does not navigate when nobody is signed in', () => {
    authStatus = { authentication_skipped: false };
    render(<Home />);

    expect(replace).not.toHaveBeenCalled();
    expect(screen.getByText(/checking sign-in/i)).toBeInTheDocument();
  });

  it("forwards a signed-in user to their OWN first project, not a hard-coded one", () => {
    authStatus = { authentication_skipped: false, current_user: 'masaomi' };
    projects = [{ number: 4321 }, { number: 35611 }];
    render(<Home />);

    expect(replace).toHaveBeenCalledWith('/projects/4321');
  });

  it('forwards on a node where authentication is switched off', () => {
    authStatus = { authentication_skipped: true };
    render(<Home />);

    expect(replace).toHaveBeenCalledWith('/projects/1001');
  });

  it('waits for the project list rather than guessing a destination', () => {
    authStatus = { authentication_skipped: false, current_user: 'masaomi' };
    projectsLoading = true;
    render(<Home />);

    expect(replace).not.toHaveBeenCalled();
  });

  it('says so instead of navigating when the account has no projects', () => {
    authStatus = { authentication_skipped: false, current_user: 'masaomi' };
    projects = [];
    render(<Home />);

    expect(replace).not.toHaveBeenCalled();
    expect(screen.getByText(/no projects are available/i)).toBeInTheDocument();
  });
});
