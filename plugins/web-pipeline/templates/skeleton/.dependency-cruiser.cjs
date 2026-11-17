// The architecture as build-breaking rules (CLAUDE.md, "Architecture"). Don't loosen a rule to get green: if one
// is wrong, stop and say so. The unattended runner refuses a change to this file.
/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: 'features-stand-alone',
      comment: 'A feature never imports another feature. Share through src/components or src/api.',
      severity: 'error',
      from: { path: '^src/features/([^/]+)/' },
      to: { path: '^src/features/([^/]+)/', pathNot: '^src/features/$1/' },
    },
    {
      name: 'components-are-presentational',
      comment: 'Shared components know nothing about the backend, the features or the app shell.',
      severity: 'error',
      from: { path: '^src/components/' },
      to: { path: '^src/(api|features|app)/' },
    },
    {
      name: 'api-is-a-leaf',
      comment: 'The API layer has no UI: it imports nothing from components, features or the app shell.',
      severity: 'error',
      from: { path: '^src/api/' },
      to: { path: '^src/(components|features|app)/' },
    },
    {
      name: 'only-the-shell-knows-everything',
      comment: 'Nothing imports the app shell; it wires the features together.',
      severity: 'error',
      from: { path: '^src/', pathNot: '^src/(app/|main\\.tsx$)' },
      to: { path: '^src/app/' },
    },
    {
      name: 'no-circular',
      comment: 'No import cycles.',
      severity: 'error',
      from: {},
      to: { circular: true },
    },
  ],
  options: {
    doNotFollow: { path: 'node_modules' },
    tsPreCompilationDeps: true,
    tsConfig: { fileName: 'tsconfig.json' },
    enhancedResolveOptions: { extensions: ['.ts', '.tsx', '.js'] },
  },
};
