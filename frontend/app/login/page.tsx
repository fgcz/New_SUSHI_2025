'use client';

import React, { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/providers/AuthContext';
import { authApi } from '@/lib/api';
import { BfabricDeviceStart } from '@/lib/types/auth';

export default function LoginPage() {
  const [login, setLogin] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const router = useRouter();
  const { authStatus, loading: authLoading } = useAuth();

  // ----- B-Fabric sign-in ---------------------------------------------------
  const [device, setDevice] = useState<BfabricDeviceStart | null>(null);
  const [bfError, setBfError] = useState('');
  const [bfBusy, setBfBusy] = useState(false);
  const [allowWrite, setAllowWrite] = useState(true);
  const [copied, setCopied] = useState(false);
  const popupRef = useRef<Window | null>(null);

  // Redirect to home page if already logged in
  useEffect(() => {
    if (!authLoading && authStatus?.current_user) {
      router.push('/');
    }
  }, [authStatus, authLoading, router]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      // Use JWT authentication (supports both standard and LDAP)
      const result = await authApi.login(login, password);

      if (result.access_token) {
        // Login successful
        router.push('/');
      } else {
        setError('Login failed');
      }
    } catch (err: any) {
      console.error('Login error:', err);
      setError(err.message || 'Network error occurred');
    } finally {
      setLoading(false);
    }
  };

  const startBfabric = async () => {
    setBfError('');
    setCopied(false);
    setBfBusy(true);

    // Open the window NOW, synchronously inside the click handler. A window opened later —
    // after the fetch resolves — is a pop-up blocker's textbook case and is discarded
    // silently, leaving a user staring at a code with nowhere to type it.
    const popup = window.open(
      'about:blank',
      'bfabric-login',
      'width=520,height=700,menubar=no,toolbar=no,location=yes',
    );
    popupRef.current = popup;

    try {
      const start = await authApi.startBfabricDeviceLogin(allowWrite);
      // Prefer B-Fabric's own no-typing URL if it ever starts sending one; otherwise our
      // constructed guess, which the approval page may or may not honour. Either way the
      // code is shown below, so a page that ignores the parameter costs a paste, not a
      // failed sign-in.
      const url =
        start.verification_uri_complete || start.verification_uri_guess || start.verification_uri;
      if (popup && !popup.closed) {
        popup.location.href = url;
      }
      setDevice(start);
    } catch (err: any) {
      popup?.close();
      setBfError(err.message || 'Could not start the B-Fabric sign-in');
      setBfBusy(false);
    }
  };

  const cancelBfabric = () => {
    popupRef.current?.close();
    setDevice(null);
    setBfBusy(false);
    setBfError('');
  };

  // Poll until the human approves. The backend enforces the interval as well, so a bug
  // here cannot turn this page into a load generator pointed at B-Fabric.
  useEffect(() => {
    if (!device) return;

    let cancelled = false;
    let timer: ReturnType<typeof setTimeout>;
    const deadline = Date.now() + device.expires_in * 1000;

    const tick = async () => {
      if (cancelled) return;

      if (Date.now() > deadline) {
        popupRef.current?.close();
        setBfError('The sign-in was not approved in time. Please start again.');
        setDevice(null);
        setBfBusy(false);
        return;
      }

      try {
        const result = await authApi.pollBfabricDeviceLogin(device.handle);
        if (cancelled) return;

        if (result.status === 'ok') {
          popupRef.current?.close();
          router.push('/');
          return;
        }

        const seconds = result.retry_in && result.retry_in > 0 ? result.retry_in : device.interval;
        timer = setTimeout(tick, seconds * 1000);
      } catch (err: any) {
        if (cancelled) return;
        popupRef.current?.close();
        setBfError(err.message || 'The B-Fabric sign-in failed');
        setDevice(null);
        setBfBusy(false);
      }
    };

    timer = setTimeout(tick, device.interval * 1000);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [device, router]);

  // Loading authentication status
  if (authLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600 mx-auto"></div>
          <p className="mt-2 text-gray-600">Loading...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8">
        <div>
          <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
            Sign in to Sushi
          </h2>
        </div>

        {authStatus?.bfabric_oidc && (
          <div className="space-y-4">
            {!device ? (
              <>
                <button
                  type="button"
                  onClick={startBfabric}
                  disabled={bfBusy}
                  className="w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {bfBusy ? 'Opening B-Fabric…' : 'Sign in with B-Fabric'}
                </button>
                <label className="flex items-center justify-center text-xs text-gray-600">
                  <input
                    type="checkbox"
                    checked={allowWrite}
                    onChange={(e) => setAllowWrite(e.target.checked)}
                    className="mr-2"
                  />
                  Allow this session to submit jobs
                </label>
                <p className="text-center text-xs text-gray-500">
                  Your password is typed at B-Fabric and never reaches this application.
                </p>
              </>
            ) : (
              <div className="rounded-md border border-brand-200 bg-brand-50 p-4 space-y-3">
                <p className="text-sm text-gray-700">
                  Approve the sign-in in the B-Fabric window. If the code is not already
                  filled in, enter it there:
                </p>
                <div className="flex items-center justify-center gap-3">
                  <code className="text-2xl font-mono tracking-widest text-gray-900">
                    {device.user_code}
                  </code>
                  <button
                    type="button"
                    onClick={() => {
                      navigator.clipboard?.writeText(device.user_code);
                      setCopied(true);
                    }}
                    className="text-xs text-brand-700 underline"
                  >
                    {copied ? 'copied' : 'copy'}
                  </button>
                </div>
                <div className="flex items-center justify-center text-sm text-gray-600">
                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-brand-600 mr-2"></div>
                  Waiting for approval…
                </div>
                {/* The window can be blocked or closed by accident; never leave the user
                    with a code and no way to use it. */}
                <p className="text-center text-xs text-gray-500">
                  No window?{' '}
                  <a
                    href={device.verification_uri_complete || device.verification_uri_guess}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-brand-700 underline"
                  >
                    Open the approval page
                  </a>
                </p>
                <button
                  type="button"
                  onClick={cancelBfabric}
                  className="w-full text-xs text-gray-500 underline"
                >
                  Cancel
                </button>
              </div>
            )}

            {bfError && (
              <div className="bg-red-50 border border-red-200 rounded-md p-3">
                <p className="text-sm text-red-800">{bfError}</p>
              </div>
            )}

            <div className="relative">
              <div className="absolute inset-0 flex items-center">
                <div className="w-full border-t border-gray-300"></div>
              </div>
              <div className="relative flex justify-center text-xs">
                <span className="bg-gray-50 px-2 text-gray-500">or</span>
              </div>
            </div>
          </div>
        )}

        <form className="space-y-6" onSubmit={handleSubmit}>
          <p className="text-center text-sm text-gray-600">
            Use your LDAP credentials to access the application
          </p>
          <div className="rounded-md shadow-sm -space-y-px">
            <div>
              <label htmlFor="login" className="sr-only">
                Username
              </label>
              <input
                id="login"
                name="login"
                type="text"
                required
                className="appearance-none rounded-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-t-md focus:outline-none focus:ring-brand-500 focus:border-brand-500 focus:z-10 sm:text-sm"
                placeholder="Username"
                value={login}
                onChange={(e) => setLogin(e.target.value)}
              />
            </div>
            <div>
              <label htmlFor="password" className="sr-only">
                Password
              </label>
              <input
                id="password"
                name="password"
                type="password"
                required
                className="appearance-none rounded-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-b-md focus:outline-none focus:ring-brand-500 focus:border-brand-500 focus:z-10 sm:text-sm"
                placeholder="Password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>
          </div>

          {error && (
            <div className="bg-red-50 border border-red-200 rounded-md p-4">
              <div className="flex">
                <div className="ml-3">
                  <h3 className="text-sm font-medium text-red-800">
                    {error}
                  </h3>
                </div>
              </div>
            </div>
          )}

          <div>
            <button
              type="submit"
              disabled={loading}
              className="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-gray-600 hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? (
                <div className="flex items-center">
                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
                  Signing in...
                </div>
              ) : (
                'Sign in'
              )}
            </button>
          </div>

          <div className="text-center">
            <Link
              href="/"
              className="font-medium text-brand-600 hover:text-brand-500"
            >
              Back to Home
            </Link>
          </div>
        </form>
      </div>
    </div>
  );
}
