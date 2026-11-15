import { render, screen } from '@testing-library/react';
import { axe } from 'vitest-axe';

import { HomePage } from './HomePage';

describe('HomePage', () => {
  it('shows the welcome title as the page heading', () => {
    render(<HomePage />);
    expect(screen.getByRole('heading', { level: 1, name: 'Welcome' })).toBeInTheDocument();
  });

  it('has no accessibility violations', async () => {
    const { container } = render(<HomePage />);
    expect(await axe(container)).toHaveNoViolations();
  });
});
