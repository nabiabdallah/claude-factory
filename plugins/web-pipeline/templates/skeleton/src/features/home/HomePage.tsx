import { PageTitle } from '../../components/PageTitle';

/** The start page. Replace it with the first real screen; keep one feature per directory. */
export function HomePage() {
  return (
    <section>
      <PageTitle>Welcome</PageTitle>
      <p className="mt-2 text-slate-700">This is the start page of app-skeleton. Features go in src/features.</p>
    </section>
  );
}
