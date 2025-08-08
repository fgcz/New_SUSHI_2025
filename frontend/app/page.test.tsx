import React from 'react';
import { render, screen } from '@testing-library/react';
import Home from './page';

// Mock AuthContext to control authentication state
jest.mock('@/contexts/AuthContext', () => {
  const React = require('react');
  const mockValue = {
    authStatus: {
      standard_login: false,
      oauth2_login: false,
      two_factor_auth: false,
      ldap_auth: false,
      wallet_auth: false,
      enabled_methods: [],
      authentication_skipped: true,
      current_user: 'Anonymous',
    },
    loading: false,
    error: null,
    refetch: jest.fn(async () => {}),
    logout: jest.fn(),
  };
  return {
    useAuth: () => mockValue,
    AuthProvider: ({ children }: { children: React.ReactNode }) => children,
  };
});

// Mock Next.js components
jest.mock('next/image', () => {
  return function MockImage({ src, alt, ...props }: any) {
    // Remove fill prop to avoid React warning
    const { fill, ...restProps } = props;
    return <img src={src} alt={alt} {...restProps} />;
  };
});

jest.mock('next/link', () => {
  return function MockLink({ href, children, ...props }: any) {
    return <a href={href} {...props}>{children}</a>;
  };
});

describe('Home Page', () => {
  it('renders Sushi title', () => {
    render(<Home />);
    
    const title = screen.getByText('Sushi');
    expect(title).toBeInTheDocument();
  });

  it('displays project number in header', () => {
    render(<Home />);
    
    // Use getAllByText to get all instances and check the header one
    const projectElements = screen.getAllByText(/Project 38222/);
    expect(projectElements.length).toBeGreaterThan(0);
    
    // Check that at least one is in the header (span element)
    const headerProject = screen.getByText('Project 38222', { selector: 'span' });
    expect(headerProject).toBeInTheDocument();
  });

  it('displays project number in main content', () => {
    render(<Home />);
    
    // Check the main content heading
    const mainProject = screen.getByText('Project 38222', { selector: 'h2' });
    expect(mainProject).toBeInTheDocument();
  });

  it('displays user name', () => {
    render(<Home />);
    
    const userText = screen.getByText(/Hi, Anonymous/);
    expect(userText).toBeInTheDocument();
  });

  it('renders all menu items in cards', () => {
    render(<Home />);
    
    const menuItems = [
      'DataSets',
      'Import DataSet', 
      'Check Jobs',
      'gStore'
    ];
    
    menuItems.forEach(item => {
      // Use getAllByText and check that at least one is an h3 (card title)
      const menuElements = screen.getAllByText(item);
      const cardTitle = menuElements.find(element => element.tagName === 'H3');
      expect(cardTitle).toBeInTheDocument();
    });
  });

  it('renders navigation links in header', () => {
    render(<Home />);
    
    const navLinks = [
      'DataSets',
      'Import',
      'Jobs', 
      'gStore',
      'Help'
    ];
    
    navLinks.forEach(link => {
      // Use getAllByText and check that at least one is a link in nav
      const linkElements = screen.getAllByText(link);
      const navLink = linkElements.find(element => 
        element.tagName === 'A' && element.closest('nav')
      );
      expect(navLink).toBeInTheDocument();
    });
  });

  it('displays footer text', () => {
    render(<Home />);
    
    const footerText = screen.getByText('SUSHI - produced by Functional Genomics Center Zurich and SIB');
    expect(footerText).toBeInTheDocument();
  });

  it('renders menu cards with correct descriptions', () => {
    render(<Home />);
    
    // Check for specific descriptions
    expect(screen.getByText(/You can see, edit and delete DataSets/)).toBeInTheDocument();
    expect(screen.getByText(/Import a DataSet from .tsv file/)).toBeInTheDocument();
    expect(screen.getByText(/Check your submitted jobs and the status/)).toBeInTheDocument();
    expect(screen.getByText(/Show result folder/)).toBeInTheDocument();
  });

  it('renders sign out link', () => {
    render(<Home />);
    
    // When authentication is skipped, Auth Status link is shown instead of Sign out
    const authStatusLink = screen.getByText('Auth Status');
    expect(authStatusLink).toBeInTheDocument();
  });

  it('renders all menu card images', () => {
    render(<Home />);
    
    const expectedImages = [
      { alt: 'DataSets icon', src: '/images/tamago.png' },
      { alt: 'Import DataSet icon', src: '/images/tako.png' },
      { alt: 'Check Jobs icon', src: '/images/maguro.png' },
      { alt: 'gStore icon', src: '/images/uni.png' }
    ];
    
    expectedImages.forEach(({ alt, src }) => {
      const image = screen.getByAltText(alt);
      expect(image).toBeInTheDocument();
      expect(image).toHaveAttribute('src', src);
    });
  });
}); 
