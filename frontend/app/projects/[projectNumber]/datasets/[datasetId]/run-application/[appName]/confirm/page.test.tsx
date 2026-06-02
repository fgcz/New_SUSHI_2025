import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';
import ConfirmJobPage from './page';

const mockPush = vi.fn();
const mockBack = vi.fn();
const mockRouter = { push: mockPush, back: mockBack, forward: vi.fn(), refresh: vi.fn(), replace: vi.fn(), prefetch: vi.fn() };

vi.mock('next/navigation', () => ({
  useParams: () => ({ projectNumber: '1001', datasetId: '1', appName: 'TestApp' }),
  useRouter: () => mockRouter,
}));

const mockJobData = {
  projectNumber: 1001,
  datasetId: 1,
  appName: 'TestApp',
  nextDataset: {
    name: 'TestApp_RNA-seq_2024-01-15',
    comment: 'Test run comment',
  },
  parameters: {
    cores: 4,
    ram: 16,
    inputFile: '/data/input.csv',
  },
};

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

describe('ConfirmJobPage', () => {

  beforeEach(() => {
    mockPush.mockClear();
    mockBack.mockClear();
    localStorage.clear();
  });

  it('renders loading skeleton initially', () => {
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mockJobData));
    renderWithProviders(<ConfirmJobPage />);
    expect(document.querySelector('.animate-pulse')).toBeInTheDocument();
  });

  it('displays error when no job data in localStorage', async () => {
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('No Job Data Found')).toBeInTheDocument();
    });
    expect(screen.getByText(/No job data found/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '← Back to Application Form' })).toBeInTheDocument();
  });

  it('displays error when job data does not match URL params', async () => {
    const mismatchedData = { ...mockJobData, projectNumber: 9999 };
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mismatchedData));
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('No Job Data Found')).toBeInTheDocument();
    });
    expect(screen.getByText(/Job data does not match current page/)).toBeInTheDocument();
  });

  it('displays page title and application info after loading', async () => {
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mockJobData));
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('Confirm Job Submission')).toBeInTheDocument();
    });
    expect(screen.getByText('Application: TestApp')).toBeInTheDocument();
    expect(screen.getByText(/Dataset:/)).toBeInTheDocument();
  });

  it('displays breadcrumbs', async () => {
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mockJobData));
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('Confirm Job Submission')).toBeInTheDocument();
    });
    expect(screen.getByText('Project 1001')).toBeInTheDocument();
    expect(screen.getByText('Datasets')).toBeInTheDocument();
    expect(screen.getByText('Confirm')).toBeInTheDocument();
  });

  it('displays result dataset section', async () => {
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mockJobData));
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('Result Dataset')).toBeInTheDocument();
    });
    expect(screen.getByText('TestApp_RNA-seq_2024-01-15')).toBeInTheDocument();
    expect(screen.getByText('Test run comment')).toBeInTheDocument();
  });

  it('displays application parameters section', async () => {
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mockJobData));
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('Application Parameters')).toBeInTheDocument();
    });
    expect(screen.getByText('cores')).toBeInTheDocument();
    expect(screen.getByText('4')).toBeInTheDocument();
    expect(screen.getByText('ram')).toBeInTheDocument();
    expect(screen.getByText('16')).toBeInTheDocument();
  });

  it('displays submit and mock run buttons', async () => {
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mockJobData));
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('Confirm Job Submission')).toBeInTheDocument();
    });
    expect(screen.getByRole('button', { name: 'Confirm & Submit Job' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Mock Run (Preview)' })).toBeInTheDocument();
  });

  it('displays back to edit button', async () => {
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mockJobData));
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('Confirm Job Submission')).toBeInTheDocument();
    });
    expect(screen.getByRole('button', { name: '← Back to Edit' })).toBeInTheDocument();
  });

  it('calls router.back when back button is clicked', async () => {
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mockJobData));
    const { user } = renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('Confirm Job Submission')).toBeInTheDocument();
    });
    await user.click(screen.getByRole('button', { name: '← Back to Edit' }));
    expect(mockBack).toHaveBeenCalled();
  });

  it('displays error when dataset API fails', async () => {
    localStorage.setItem('omics_job_submission_data', JSON.stringify(mockJobData));
    server.use(
      http.get('*/api/v1/datasets/:datasetId', () => {
        return new HttpResponse(null, { status: 500 });
      })
    );
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('Failed to load dataset')).toBeInTheDocument();
    });
  });

  it('shows empty parameters message when no parameters', async () => {
    const dataWithoutParams = { ...mockJobData, parameters: {} };
    localStorage.setItem('omics_job_submission_data', JSON.stringify(dataWithoutParams));
    renderWithProviders(<ConfirmJobPage />);
    await waitFor(() => {
      expect(screen.getByText('Application Parameters')).toBeInTheDocument();
    });
    expect(screen.getByText('No parameters configured')).toBeInTheDocument();
  });

});
