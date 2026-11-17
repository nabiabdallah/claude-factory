import type { ReactNode } from 'react';

/** The one h1 of a page. */
export function PageTitle({ children }: { children: ReactNode }) {
  return <h1 className="text-2xl font-semibold text-slate-900">{children}</h1>;
}
