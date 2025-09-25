import React from 'react';
import { screen, fireEvent, waitFor } from '@testing-library/react';
import { renderWithQuery } from '@/test-utils/test-utils';
import ProjectDatasetsPage from './page';

jest.mock('next/navigation', () => {
  const actual = jest.requireActual('next/navigation');
  return {
    ...actual,
    useRouter: () => ({
      push: jest.fn(),
    }),
    usePathname: () => '/projects/1001/datasets',
    useParams: () => ({ projectNumber: '1001' }),
    useSearchParams: () => {
      const params = new URLSearchParams();
      return {
        get: (key: string) => params.get(key),
        toString: () => params.toString(),
        // Minimal subset used by component via new URLSearchParams(searchParams)
        [Symbol.iterator]: params[Symbol.iterator].bind(params),
        entries: params.entries.bind(params),
        keys: params.keys.bind(params),
        values: params.values.bind(params),
        forEach: params.forEach.bind(params),
      } as unknown as URLSearchParams;
    },
  };
});

jest.mock('@/lib/api', () => {
  return {
    projectApi: {
      getProjectDatasets: jest.fn(async (_projectNumber: number, _params: any) => ({
        datasets: [
          {
            id: 1,
            name: 'Dataset 1',
            sushi_app_name: 'AppA',
            completed_samples: 2,
            samples_length: 3,
            parent_id: null,
            children_ids: [3],
            user_login: 'tester',
            created_at: new Date('2024-01-01T10:00:00Z').toISOString(),
            bfabric_id: 111,
            project_number: 1001,
          },
          {
            id: 2,
            name: 'Dataset 2',
            sushi_app_name: '',
            completed_samples: 0,
            samples_length: 0,
            parent_id: 1,
            children_ids: [],
            user_login: 'tester',
            created_at: new Date('2024-01-02T10:00:00Z').toISOString(),
            bfabric_id: null,
            project_number: 1001,
          },
        ],
        total_count: 2,
        page: 1,
        per: 50,
        project_number: 1001,
      })),
    },
  };
});

describe('ProjectDatasetsPage', () => {
  it('renders title and table headings', async () => {
    renderWithQuery(<ProjectDatasetsPage />);
    expect(await screen.findByText('Project 1001 - DataSets')).toBeInTheDocument();
    expect(screen.getByText('ID')).toBeInTheDocument();
    expect(screen.getByText('Name')).toBeInTheDocument();
    expect(screen.getByText('SushiApp')).toBeInTheDocument();
  });

  it('renders dataset rows and links', async () => {
    renderWithQuery(<ProjectDatasetsPage />);
    expect(await screen.findByText('Dataset 1')).toBeInTheDocument();
    expect(screen.getByText('Dataset 2')).toBeInTheDocument();
    // Link to dataset details
    const link = screen.getByRole('link', { name: 'Dataset 1' });
    expect(link).toHaveAttribute('href', '/projects/1001/datasets/1');
  });

  it('handles search submit and per change', async () => {
    const { container } = renderWithQuery(<ProjectDatasetsPage />);
    await screen.findByText('Dataset 1');

    const input = container.querySelector('input[placeholder="Search name..."]') as HTMLInputElement;
    fireEvent.change(input, { target: { value: 'Dataset 1' } });
    const searchButton = screen.getByRole('button', { name: 'Search' });
    fireEvent.click(searchButton);

    const select = screen.getByDisplayValue('50') as HTMLSelectElement;
    fireEvent.change(select, { target: { value: '25' } });
  });

  it('toggles select all and single selection', async () => {
    renderWithQuery(<ProjectDatasetsPage />);
    await screen.findByText('Dataset 1');

    // Select all on page
    const selectAll = screen.getAllByRole('checkbox')[0] as HTMLInputElement;
    fireEvent.click(selectAll);
    // Toggle single
    const rowCheckboxes = screen.getAllByRole('checkbox').slice(1) as HTMLInputElement[];
    fireEvent.click(rowCheckboxes[0]);
  });

  it('shows pagination summary', async () => {
    renderWithQuery(<ProjectDatasetsPage />);
    await screen.findByText('Dataset 1');
    expect(screen.getByText(/Showing 1 to 2 of 2 entries/)).toBeInTheDocument();
  });
});


