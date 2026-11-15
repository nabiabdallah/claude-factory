import { Component, type ErrorInfo, type ReactNode } from 'react';

import { PageTitle } from '../components/PageTitle';

interface Props {
  children: ReactNode;
  /** Where the error is reported; the default writes to the console. Never pass user data along. */
  onError?: (error: Error, info: ErrorInfo) => void;
}

interface State {
  failed: boolean;
}

/** Catches a rendering error below it and shows a plain message instead of a blank page. */
export class ErrorBoundary extends Component<Props, State> {
  override state: State = { failed: false };

  static getDerivedStateFromError(): State {
    return { failed: true };
  }

  override componentDidCatch(error: Error, info: ErrorInfo): void {
    if (this.props.onError) this.props.onError(error, info);
    else console.error('A page failed to render', error.name);
  }

  override render(): ReactNode {
    if (!this.state.failed) return this.props.children;
    return (
      <section role="alert">
        <PageTitle>Something went wrong</PageTitle>
        <p className="mt-2 text-slate-700">This page could not be shown. Reload it to try again.</p>
      </section>
    );
  }
}
