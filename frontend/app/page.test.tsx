import React from 'react';
import { render, screen, waitFor, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import Home from './page';

// Mock fetch globally
const mockFetch = jest.fn();
global.fetch = mockFetch;

describe('Home Page', () => {
  beforeEach(() => {
    mockFetch.mockClear();
  });

  it('renders SUSHI System title', () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ message: 'Hello, World!' }),
    });

    render(<Home />);
    
    const title = screen.getByText('SUSHI System');
    expect(title).toBeInTheDocument();
  });

  it('shows loading state initially', () => {
    mockFetch.mockImplementationOnce(() => new Promise(() => {})); // Never resolves

    render(<Home />);
    
    const loadingText = screen.getByText('読み込み中...');
    expect(loadingText).toBeInTheDocument();
  });

  it('displays API message when fetch succeeds', async () => {
    const testMessage = 'Hello, World!';
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ message: testMessage }),
    });

    render(<Home />);
    
    await waitFor(() => {
      const apiMessage = screen.getByText(`APIからのメッセージ: ${testMessage}`);
      expect(apiMessage).toBeInTheDocument();
    });
  });

  it('displays error message when fetch fails', async () => {
    mockFetch.mockRejectedValueOnce(new Error('Network error'));

    render(<Home />);
    
    await waitFor(() => {
      const errorMessage = screen.getByText('エラーが発生しました：');
      expect(errorMessage).toBeInTheDocument();
    });
  });

  it('displays retry button on error', async () => {
    mockFetch.mockRejectedValueOnce(new Error('Network error'));

    render(<Home />);
    
    await waitFor(() => {
      const retryButton = screen.getByText('再試行');
      expect(retryButton).toBeInTheDocument();
    });
  });

  it('retries API call when retry button is clicked', async () => {
    const user = userEvent.setup();
    
    // First call fails
    mockFetch.mockRejectedValueOnce(new Error('Network error'));
    
    render(<Home />);
    
    // Wait for error to appear
    await waitFor(() => {
      expect(screen.getByText('エラーが発生しました：')).toBeInTheDocument();
    });

    // Second call succeeds
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ message: 'Success!' }),
    });

    // Click retry button with act wrapper
    const retryButton = screen.getByText('再試行');
    await act(async () => {
      await user.click(retryButton);
    });

    // Wait for the second call to complete
    await waitFor(() => {
      expect(mockFetch).toHaveBeenCalledTimes(2);
    });
  });
}); 