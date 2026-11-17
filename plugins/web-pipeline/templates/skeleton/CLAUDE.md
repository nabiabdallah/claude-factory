# app-skeleton

A single-page web UI: React, TypeScript and Vite, styled with Tailwind CSS. Built by the claude-factory
`web-pipeline` (factory ADR 0035).

## Commands

- `npm ci`: install exactly what `package-lock.json` says. Never `npm install` in CI.
- `npm run dev`: local server; `/api` goes to the service on `localhost:8080`.
- `npm run verify`: typecheck, lint (zero warnings), architecture rules, tests with coverage, build, bundle
  budget. Run it before calling anything done, and report the real result.

## Architecture

The rules are in `.dependency-cruiser.cjs` and `eslint.config.js`, and they fail the build. Never loosen a rule or
delete a test to get green; if a rule blocks you, stop and explain.

- `src/api/`: the only code that talks to the backend. Nothing else calls `fetch`.
- `src/components/`: shared, presentational components. They know nothing of the API, features or shell.
- `src/features/<name>/`: one folder per feature. A feature never imports another feature.
- `src/app/`: the shell (layout, routes, error boundary). Nothing imports it except `src/main.tsx`.

## Rules

- Tests first: write or update the failing test, then the code. Every screen has a test for its states (loading,
  empty, error, filled) and an axe check.
- The coverage floor (80% lines, 70% branches, in `vite.config.ts`) is raise-only.
- The bundle budget in `scripts/check-bundle.mjs` is raised only in a reviewed change that says why.
- Exact versions only (`.npmrc` has `save-exact`). Don't add a dependency without saying why.
- Never put secrets, tokens or personal data in the code, the bundle or the logs. Show a problem's `title` to
  people, never the whole document.
- Decisions go in `docs/adr/`, specs in `docs/specs/`.
