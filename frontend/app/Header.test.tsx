import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import Header from './Header';

// All three behaviours pinned here were reported by a human clicking the UI on a node
// that requires a login — the state no test had ever rendered the header in.

const logout = vi.fn();
let authStatus: { authentication_skipped: boolean; current_user?: string } | null = {
  authentication_skipped: false,
  current_user: 'masaomi',
};

vi.mock('@/providers/AuthContext', () => ({
  useAuth: () => ({ authStatus, logout, loading: false, error: null }),
}));

// An FGCZ employee really is a member of this many projects; the account this was
// found with has 77, with the one they wanted 70th in numeric order.
const MANY_PROJECTS = Array.from({ length: 77 }, (_, i) => ({ number: 1001 + i * 450 }))
  .concat([{ number: 35611 }]);

vi.mock('@/lib/hooks', () => ({
  useProjectList: () => ({
    userProjects: { projects: MANY_PROJECTS },
    isLoading: false,
    error: null,
    isEmpty: false,
    refetch: vi.fn(),
  }),
}));

vi.mock('@/lib/api', () => ({
  projectApi: { validateDatasetId: vi.fn() },
}));

describe('Header', () => {
  beforeEach(() => {
    logout.mockClear();
    authStatus = { authentication_skipped: false, current_user: 'masaomi' };
  });

  describe('signing out', () => {
    // The button existed but was inside a JSX comment, so a logged-in user had no way
    // to end the session: the token sits in localStorage and nothing else clears it.
    it('offers Sign out when authentication is required', () => {
      render(<Header />);

      const signOut = screen.getByRole('button', { name: /sign out/i });
      fireEvent.click(signOut);

      expect(logout).toHaveBeenCalledTimes(1);
    });

    it('shows the Auth Skipped badge instead when there is no authentication', () => {
      authStatus = { authentication_skipped: true, current_user: 'anonymous' };
      render(<Header />);

      expect(screen.getByText(/auth skipped/i)).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /sign out/i })).not.toBeInTheDocument();
    });
  });

  describe('the projects dropdown', () => {
    function openDropdown() {
      render(<Header />);
      fireEvent.click(screen.getByRole('button', { name: /projects/i }));
    }

    it('renders every project the user belongs to, including the last ones', () => {
      openDropdown();

      // 35611 is 70th of 77 for this account. It WAS rendered before the fix and still
      // unreachable, so presence alone is not the property that matters — see below.
      expect(screen.getByRole('link', { name: 'Project 35611' }))
        .toHaveAttribute('href', '/projects/35611');
    });

    it('caps its height and keeps the scroll inside itself', () => {
      openDropdown();

      const panel = screen.getByRole('link', { name: 'Project 35611' }).parentElement!;

      // Without a height cap the list runs past the bottom of the viewport and the
      // projects sorted last cannot be clicked at all.
      expect(panel.className).toMatch(/max-h-/);
      expect(panel.className).toMatch(/overflow-y-auto/);
      // Without this the wheel chains to the document once the list ends, which is why
      // the main screen scrolled along with the menu.
      expect(panel.className).toMatch(/overscroll-contain/);
    });
  });
});
