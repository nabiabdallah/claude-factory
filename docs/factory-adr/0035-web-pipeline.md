# 0035. A second pipeline for web frontends, and one runner for every pipeline

- Status: Accepted
- Date: 2026-11-15
- Deciders: Noel Abi Abdallah
- Amends: [ADR 0029](0029-scope-freeze-and-definition-of-done.md) (when the frontend pipeline may start)

## Context
The factory builds Java backends only. A product also needs a UI, and ADR 0029 noted that one would be built
outside the factory or wait. `docs/plans/frontend-pipeline.md` (proposed 2026-11-11) laid out a second plugin with
seven choices for the owner. ADR 0029's amendment allowed building it during the week of unattended maintenance.
That week has not started: the cluster's VM is waiting for capacity at Oracle, which is waiting, not work.

## Decision
The owner approved the plan with all seven recommendations on 2026-11-15, and said to start now.
- **A plugin `web-pipeline`** in the same marketplace, shaped like `java-pipeline`: spec, plan, review, failing
  tests, code, verify, review, pull request; the same guardrails and the same unattended runs.
- **The seven choices:** React + TypeScript + Vite, a single-page app; a UI lives in its own repository;
  it ships as a container (unprivileged nginx serving static files) on the same cluster; Tailwind CSS with
  shadcn/ui components copied into the repository; login by OIDC authorization code + PKCE, added by a skill;
  the UI generates a typed client from the service's OpenAPI document and fails the build on drift; end-to-end
  tests with Playwright against a mocked API. npm with a committed lockfile; Node LTS pinned.
- **One runner for every pipeline (step F0).** `factory-run.sh` stays one file, identical in every template of
  every plugin. What differs per project is in `.github/factory.conf`: the plugin, the verify command, the
  project's protected files, where its tests are, and its build file with what may not be added to it. The
  runner reads the file as committed on the base commit, never from the agent's tree, and `.github/` is
  protected in every project, so a run can't choose its own gate. Values are data: the verify command is run as
  arguments, not through a shell. Without the file a project is a Java service, as before.
- **Timing (amends ADR 0029):** the frontend pipeline may be built while C1 waits for its VM, not only during the
  maintenance week. The rest of that amendment stands: it is a separate plugin, and nothing in it changes
  market-rates or the maintenance setup.
- **Steps F0 to F6** are in the roadmap, outside the unattended queue. F2 (the agents) waits for the owner's
  word on its order with A5 (domain rules out of the agents), which the plan recommends first and ADR 0029 defers.

## Alternatives considered
The plan lists one per choice (Next.js or Vue; a monorepo; a static host; MUI; a backend-for-frontend; hand-written
fetch calls; end-to-end tests against the real service). For the runner:
- **A second runner script for web projects:** two copies of the gate to keep equally strict; a fix to one is
  forgotten in the other.
- **Environment variables in the workflow instead of a file:** the workflow is per template already, but the gate
  job would then take its rules from a file the same pull request can't change either way; a file read from the
  base commit is the one place both the workflow and a person look.

## Consequences
- Positive: the web templates get the unattended runs, the gate and the two-job isolation without new code paths.
- Positive: existing services need nothing: no `factory.conf` means the Java values.
- Negative: two pipelines double the release and upgrade work until template drift is automated (ADR 0032).
- Negative: the scope freeze of ADR 0029 is loosened a second time; C1's acceptance still comes first when the
  VM exists.
