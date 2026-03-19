import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import ProjectPage from './page';

vi.mock('next/navigation', () => ({
  useParams: () => ({ projectNumber: '1001' }),
}));

vi.mock('next/image', () => ({
  default: ({ alt, ...props }: { alt: string; [key: string]: unknown }) => (
    // eslint-disable-next-line @next/next/no-img-element
    <img alt={alt} {...props} />
  ),
}));

describe('ProjectPage', () => {

  it('renders page title with project number', () => {
    render(<ProjectPage />);
    // Title appears in both breadcrumb and h2 heading
    expect(screen.getAllByText('Project 1001').length).toBeGreaterThanOrEqual(1);
    expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('Project 1001');
  });

  it('renders DataSets menu card with correct link', () => {
    render(<ProjectPage />);
    expect(screen.getByText('DataSets')).toBeInTheDocument();
    const datasetsLink = screen.getByRole('link', { name: /DataSets/i });
    expect(datasetsLink).toHaveAttribute('href', '/projects/1001/datasets');
  });

  it('renders Import DataSet menu card with correct link', () => {
    render(<ProjectPage />);
    expect(screen.getByText('Import DataSet')).toBeInTheDocument();
    const importLink = screen.getByRole('link', { name: /Import DataSet/i });
    expect(importLink).toHaveAttribute('href', '/projects/1001/datasets/import');
  });

  it('renders Check Jobs menu card with correct link', () => {
    render(<ProjectPage />);
    expect(screen.getByText('Check Jobs')).toBeInTheDocument();
    const jobsLink = screen.getByRole('link', { name: /Check Jobs/i });
    expect(jobsLink).toHaveAttribute('href', '/projects/1001/jobs');
  });

  it('renders gStore menu card with correct link', () => {
    render(<ProjectPage />);
    expect(screen.getByText('gStore')).toBeInTheDocument();
    const gstoreLink = screen.getByRole('link', { name: /gStore/i });
    expect(gstoreLink).toHaveAttribute('href', 'files/p1001');
  });

  it('renders all four menu cards', () => {
    render(<ProjectPage />);
    const links = screen.getAllByRole('link');
    // 4 menu cards + breadcrumb link
    expect(links.length).toBeGreaterThanOrEqual(4);
  });

  it('renders menu card icons', () => {
    render(<ProjectPage />);
    expect(screen.getByAltText('DataSets icon')).toBeInTheDocument();
    expect(screen.getByAltText('Import DataSet icon')).toBeInTheDocument();
    expect(screen.getByAltText('Check Jobs icon')).toBeInTheDocument();
    expect(screen.getByAltText('gStore icon')).toBeInTheDocument();
  });

});
