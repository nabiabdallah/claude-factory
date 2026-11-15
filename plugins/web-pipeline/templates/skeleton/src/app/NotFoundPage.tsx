import { Link } from 'react-router';

import { PageTitle } from '../components/PageTitle';

export function NotFoundPage() {
  return (
    <section>
      <PageTitle>Page not found</PageTitle>
      <p className="mt-2 text-slate-700">
        There is nothing at this address. <Link to="/" className="underline">Go to the start page</Link>.
      </p>
    </section>
  );
}
