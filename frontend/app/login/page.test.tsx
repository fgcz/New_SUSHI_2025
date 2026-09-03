import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import LoginPage from './page';

// This page had NO tests at all, and it is on the one path that only runs when a node
// REQUIRES A LOGIN — the class that produced nine defects in a single afternoon the first
// time a human signed in to 082. The B-Fabric flow adds a popup, a poll loop and a token
// hand-off, so every one of those is pinned here.

const push = vi.fn();
vi.mock('next/navigation', () => ({ useRouter: () => ({ push }) }));

let authStatus: any = { bfabric_oidc: true, ldap_auth: true, authentication_skipped: false };
vi.mock('@/providers/AuthContext', () => ({
  useAuth: () => ({ authStatus, loading: false }),
}));

const startBfabricDeviceLogin = vi.fn();
const pollBfabricDeviceLogin = vi.fn();
const login = vi.fn();
vi.mock('@/lib/api', () => ({
  authApi: {
    startBfabricDeviceLogin: (...a: any[]) => startBfabricDeviceLogin(...a),
    pollBfabricDeviceLogin: (...a: any[]) => pollBfabricDeviceLogin(...a),
    login: (...a: any[]) => login(...a),
  },
}));

const START = {
  handle: 'opaque-handle',
  user_code: 'ABCD-EFGH',
  verification_uri: 'https://bfabric.example/oauth/device.html',
  verification_uri_complete: null,
  verification_uri_guess: 'https://bfabric.example/oauth/device.html?user_code=ABCD-EFGH',
  interval: 1,
  expires_in: 900,
};

let openedWith: string | null;
let popup: any;

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers({ shouldAdvanceTime: true });
  authStatus = { bfabric_oidc: true, ldap_auth: true, authentication_skipped: false };
  openedWith = null;
  popup = { closed: false, close: vi.fn(), location: { href: '' } };
  vi.stubGlobal('open', vi.fn((url: string) => { openedWith = url; return popup; }));
  startBfabricDeviceLogin.mockResolvedValue(START);
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('the B-Fabric button', () => {
  it('is not offered on a node that has not enabled it', () => {
    authStatus = { bfabric_oidc: false, ldap_auth: true, authentication_skipped: false };
    render(<LoginPage />);
    expect(screen.queryByText(/Sign in with B-Fabric/)).toBeNull();
  });

  it('is offered when the backend advertises it, alongside the LDAP form', () => {
    render(<LoginPage />);
    expect(screen.getByText(/Sign in with B-Fabric/)).toBeTruthy();
    expect(screen.getByPlaceholderText('Username')).toBeTruthy();
  });

  it('says plainly that the password does not reach this application', () => {
    render(<LoginPage />);
    expect(screen.getByText(/never reaches this application/)).toBeTruthy();
  });
});

describe('starting a B-Fabric sign-in', () => {
  // A window opened AFTER the fetch resolves is a pop-up blocker's textbook case and is
  // discarded silently, leaving the user holding a code with nowhere to type it.
  it('opens the window synchronously in the click handler, before any request', () => {
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    expect(window.open).toHaveBeenCalled();
    expect(openedWith).toBe('about:blank');
  });

  it('sends the window to a URL carrying the code, and shows the code as well', async () => {
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(screen.getByText('ABCD-EFGH')).toBeTruthy());
    expect(popup.location.href).toBe(START.verification_uri_guess);
  });

  it('asks for job-submission scope by default, and drops it when unchecked', async () => {
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(startBfabricDeviceLogin).toHaveBeenCalledWith(true));

    fireEvent.click(screen.getByText(/Cancel/));
    fireEvent.click(screen.getByLabelText(/Allow this session to submit jobs/));
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(startBfabricDeviceLogin).toHaveBeenLastCalledWith(false));
  });

  it('closes the window and reports why when the backend refuses to start', async () => {
    startBfabricDeviceLogin.mockRejectedValue(new Error('Too many sign-ins are already in progress'));
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(screen.getByText(/Too many sign-ins/)).toBeTruthy());
    expect(popup.close).toHaveBeenCalled();
  });
});

describe('waiting for approval', () => {
  it('keeps polling while the answer is pending', async () => {
    pollBfabricDeviceLogin.mockResolvedValue({ status: 'pending' });
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(screen.getByText('ABCD-EFGH')).toBeTruthy());

    await vi.advanceTimersByTimeAsync(1000);
    await waitFor(() => expect(pollBfabricDeviceLogin).toHaveBeenCalledWith('opaque-handle'));
    expect(screen.getByText(/Waiting for approval/)).toBeTruthy();
  });

  it('lands the user in the application once approved, and closes the window', async () => {
    pollBfabricDeviceLogin.mockResolvedValue({ status: 'ok', access_token: 'a.b.c' });
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(screen.getByText('ABCD-EFGH')).toBeTruthy());

    await vi.advanceTimersByTimeAsync(1000);
    await waitFor(() => expect(push).toHaveBeenCalledWith('/'));
    expect(popup.close).toHaveBeenCalled();
  });

  // The failure reason has to survive to the screen. A permanent refusal that reads
  // "Please try again" is advice that can never work — that defect has been shipped here
  // before.
  it('shows the server\'s own reason when the sign-in fails, and does not navigate', async () => {
    pollBfabricDeviceLogin.mockRejectedValue(new Error('This sign-in was not approved in time.'));
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(screen.getByText('ABCD-EFGH')).toBeTruthy());

    await vi.advanceTimersByTimeAsync(1000);
    await waitFor(() => expect(screen.getByText(/was not approved in time/)).toBeTruthy());
    expect(push).not.toHaveBeenCalled();
    expect(popup.close).toHaveBeenCalled();
  });

  it('honours a server-supplied back-off instead of its own interval', async () => {
    pollBfabricDeviceLogin.mockResolvedValue({ status: 'pending', retry_in: 6 });
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(screen.getByText('ABCD-EFGH')).toBeTruthy());

    await vi.advanceTimersByTimeAsync(1000);
    await waitFor(() => expect(pollBfabricDeviceLogin).toHaveBeenCalledTimes(1));
    await vi.advanceTimersByTimeAsync(1500);
    expect(pollBfabricDeviceLogin).toHaveBeenCalledTimes(1); // still backing off
    await vi.advanceTimersByTimeAsync(5000);
    await waitFor(() => expect(pollBfabricDeviceLogin).toHaveBeenCalledTimes(2));
  });

  it('stops polling when the user cancels', async () => {
    pollBfabricDeviceLogin.mockResolvedValue({ status: 'pending' });
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(screen.getByText('ABCD-EFGH')).toBeTruthy());

    fireEvent.click(screen.getByText(/Cancel/));
    expect(popup.close).toHaveBeenCalled();
    const before = pollBfabricDeviceLogin.mock.calls.length;
    await vi.advanceTimersByTimeAsync(5000);
    expect(pollBfabricDeviceLogin.mock.calls.length).toBe(before);
  });

  // Never leave someone holding a code with nowhere to type it.
  it('always offers a link in case the window was blocked', async () => {
    render(<LoginPage />);
    fireEvent.click(screen.getByText(/Sign in with B-Fabric/));
    await waitFor(() => expect(screen.getByText(/Open the approval page/)).toBeTruthy());
  });
});
