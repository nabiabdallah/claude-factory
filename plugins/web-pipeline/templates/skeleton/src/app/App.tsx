import { Link, Route, Routes } from 'react-router';

import { HomePage } from '../features/home/HomePage';
import { ErrorBoundary } from './ErrorBoundary';
import { NotFoundPage } from './NotFoundPage';

/** The app shell: layout, navigation and the routes. The only place that knows every feature. */
export function App() {
  return (
    <div className="mx-auto flex min-h-screen max-w-3xl flex-col gap-6 p-6">
      <header className="flex items-center justify-between border-b border-slate-200 pb-4">
        <Link to="/" className="text-lg font-semibold text-slate-900">
          app-skeleton
        </Link>
      </header>
      <main className="flex-1">
        <ErrorBoundary>
          <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="*" element={<NotFoundPage />} />
          </Routes>
        </ErrorBoundary>
      </main>
    </div>
  );
}
