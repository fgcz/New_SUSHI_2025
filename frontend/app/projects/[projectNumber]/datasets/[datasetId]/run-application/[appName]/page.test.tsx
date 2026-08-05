import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';
import RunApplicationPage from './page';

const mockPush = vi.fn();
const mockReplace = vi.fn();
let mockSearchParams = new URLSearchParams();

vi.mock('next/navigation', () => ({
  useParams: () => ({ projectNumber: '1001', datasetId: '1', appName: 'CountQC' }),
  useRouter: () => ({ push: mockPush, replace: mockReplace }),
  useSearchParams: () => mockSearchParams,
  usePathname: () => '/projects/1001/datasets/1/run-application/CountQC',
}));

vi.stubGlobal('alert', vi.fn());

function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
        staleTime: 0,
        gcTime: 0,
      },
    },
  });
}

function renderWithProviders(ui: React.ReactElement) {
  const client = createTestQueryClient();
  return {
    client,
    user: userEvent.setup(),
    ...render(
      <QueryClientProvider client={client}>{ui}</QueryClientProvider>
    ),
  };
}

describe('RunApplicationPage', () => {
  beforeEach(() => {
    mockPush.mockClear();
    mockReplace.mockClear();
    mockSearchParams = new URLSearchParams();
  });

  it('renders loading skeleton initially', () => {
    renderWithProviders(<RunApplicationPage />);
    expect(document.querySelector('.animate-pulse')).toBeInTheDocument();
  });

  it('displays page title, breadcrumbs, and dataset info after loading', async () => {
    mockSearchParams.set('step', '1');
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Run Application: CountQC')).toBeInTheDocument();
    });
    expect(screen.getByText('Dataset: RNA-seq Analysis Dataset')).toBeInTheDocument();
    expect(screen.getByText('Project 1001')).toBeInTheDocument();
    expect(screen.getByText('Datasets')).toBeInTheDocument();
    expect(screen.getByText('RNA-seq Analysis Dataset')).toBeInTheDocument();
  });

  it('displays breadcrumbs', async () => {
    mockSearchParams.set('step', '1');
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Run Application: CountQC')).toBeInTheDocument();
    });
  });

  it('displays NextDataset section with name and comment fields', async () => {
    mockSearchParams.set('step', '1');
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('NextDataset')).toBeInTheDocument();
    });
    expect(screen.getByLabelText('Name')).toBeInTheDocument();
    expect(screen.getByLabelText('Comment')).toBeInTheDocument();
  });

  it('displays step indicator with correct steps', async () => {
    mockSearchParams.set('step', '1');
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Resource Parameters')).toBeInTheDocument();
    });
    expect(screen.getByText('Tool Parameters')).toBeInTheDocument();
  });

  it('displays first step form fields', async () => {
    mockSearchParams.set('step', '1');
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Resource Parameters')).toBeInTheDocument();
    });
    expect(screen.getByText('Number of CPU cores')).toBeInTheDocument();
    expect(screen.getByText('RAM in GB')).toBeInTheDocument();
    expect(screen.getByText('Scratch space in GB')).toBeInTheDocument();
  });

  it('has Back and Next navigation buttons', async () => {
    mockSearchParams.set('step', '1');
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Resource Parameters')).toBeInTheDocument();
    });
    expect(screen.getByRole('button', { name: /Next/i })).toBeInTheDocument();
  });

  it('navigates to next step when Next clicked', async () => {
    mockSearchParams.set('step', '1');
    const { user } = renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Resource Parameters')).toBeInTheDocument();
    });
    await user.click(screen.getByRole('button', { name: /Next/i }));
    expect(mockPush).toHaveBeenCalledWith(
      expect.stringContaining('step=2')
    );
  });

  it('displays second step fields when on step 2', async () => {
    mockSearchParams.set('step', '2');
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Tool Parameters')).toBeInTheDocument();
    });
    expect(screen.getByText('Reference genome')).toBeInTheDocument();
    expect(screen.getByText('Paired-end data')).toBeInTheDocument();
  });

  it('shows Continue to Review button on last step', async () => {
    mockSearchParams.set('step', '2');
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Tool Parameters')).toBeInTheDocument();
    });
    expect(screen.getByRole('button', { name: /Continue to Review/i })).toBeInTheDocument();
  });

  it('allows clicking on completed step to navigate back', async () => {
    mockSearchParams.set('step', '2');
    const { user } = renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Tool Parameters')).toBeInTheDocument();
    });
    const step1Button = screen.getByRole('button', { name: /Resource Parameters/i });
    await user.click(step1Button);
    expect(mockPush).toHaveBeenCalledWith(
      expect.stringContaining('step=1')
    );
  });

  it('displays error state when dataset fetch fails', async () => {
    server.use(
      http.get('*/api/v1/datasets/:datasetId', () => {
        return new HttpResponse(null, { status: 500 });
      })
    );
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Failed to load dataset')).toBeInTheDocument();
    });
  });

  it('has back to dataset link', async () => {
    mockSearchParams.set('step', '1');
    renderWithProviders(<RunApplicationPage />);
    await waitFor(() => {
      expect(screen.getByText('Run Application: CountQC')).toBeInTheDocument();
    });
    expect(screen.getByRole('link', { name: '← Back to Dataset' })).toHaveAttribute(
      'href',
      '/projects/1001/datasets/1'
    );
  });

  it('stores job data and navigates to confirm page on submit', async () => {
    mockSearchParams.set('step', '2');
    const { user } = renderWithProviders(<RunApplicationPage />);
    const localStorageSpy = vi.spyOn(Storage.prototype, 'setItem');
    await waitFor(() => {
      expect(screen.getByText('Tool Parameters')).toBeInTheDocument();
    });
    await user.click(screen.getByRole('button', { name: /Continue to Review/i }));
    expect(localStorageSpy).toHaveBeenCalledWith(
      'omics_job_submission_data',
      expect.any(String)
    );
    expect(mockPush).toHaveBeenCalledWith(
      '/projects/1001/datasets/1/run-application/CountQC/confirm'
    );
    localStorageSpy.mockRestore();
  });

});
