# Plan: frontend pipeline (`web-pipeline`)

Status: proposed 2026-11-11, waiting for the owner's OK. Not in the autonomous queue: the roadmap says each new
pipeline gets its own plan first, and seven of the choices below are the owner's. Merging this file with the
choices edited is the OK; the steps then move into the queue in `docs/ROADMAP.md` and this file is deleted when
the last one merges.

## Goal
A second plugin in the marketplace so the factory can build the UI of a product as well as its API: same shape
as `java-pipeline` (spec → plan → review → failing tests → code → verify → review → PR), same guardrails
(architecture rules that fail the build, coverage floor, supply chain, deploy gate), same unattended runs
(`factory:spec`, `factory:build`).

## Decisions for the owner
Each has a recommendation. Strike the one you don't want, or write another.

| # | Decision | Recommended | Alternative | Why the recommendation |
|---|---|---|---|---|
| 1 | Framework | React + TypeScript + Vite, single-page app | Next.js; Vue | No server to run or secure; static files behind the API. Agents write React/TS most reliably. Next.js earns its cost only if you need server rendering or SEO. |
| 2 | Where a UI lives | Its own repo per product UI | Monorepo with the service | Matches "one service, one repo, one pinned plugin"; the runner, rulesets and promotion gate work unchanged. |
| 3 | Hosting | Container (unprivileged nginx serving static files) on the same cluster | Static host (Cloudflare Pages, Vercel) | Reuses Jib-less image build, Trivy, cosign, Kustomize overlays and `check-deploy.sh`. A static host is cheaper to run but is a second deploy path to secure. |
| 4 | Components and styling | Tailwind CSS + shadcn/ui (components copied into the repo) | MUI; plain CSS modules | Components are code the agents can read and change; no heavy runtime dependency. |
| 5 | Login | OIDC authorization code + PKCE against the same issuer as `add-resource-server`, added by a skill | Session cookie via a backend-for-frontend | Pairs with what the Java template already validates. Tokens in the browser are the trade-off; a BFF is safer and a bigger build. |
| 6 | API contract | The service publishes OpenAPI; the UI generates a typed client from it and fails the build on drift | Hand-written fetch calls | Makes "contract first" in the spec template mechanical across the two repos. Needs a small change to the Java template (below). |
| 7 | End-to-end tests | Playwright against a mocked API (MSW) in CI | Playwright against the real service | Runs in one repo with no cluster. Full-stack tests wait for a real environment, like the other cluster items. |

Package manager: npm with a committed lockfile and `npm ci` (no extra tool to pin). Node: current LTS, pinned in
`.nvmrc` and CI.

## What gets built

### Plugin `plugins/web-pipeline/`
- **Agents:** `architect-reviewer` (layering, state, data fetching, contract use), `test-writer` (failing
  component and e2e tests from acceptance criteria), `code-reviewer` (correctness, security: XSS, token
  handling, no secrets in the bundle), and new: `accessibility-reviewer` (keyboard, labels, contrast, axe results).
- **Skills:** `new-project`, `new-feature`, `intake` (UI specs add screens, states and empty/error/loading
  behaviour to the template), `write-adr`, later `add-oidc-login`.
- **Hooks:** format edited files (Prettier), Stop gate running `npm run verify`.
- **Template `skeleton`:** app shell, routing, error boundary, API client layer, one example screen with tests.

### Guardrails, mirroring the Java ones
| Java pipeline | Web pipeline |
|---|---|
| ArchUnit `ArchitectureTest` | `dependency-cruiser` rules: `features/*` don't import each other; UI components don't call the network; only `api/` talks to the backend. Protected file. |
| Spotless | Prettier + ESLint (typescript-eslint strict, jsx-a11y), zero warnings |
| JaCoCo floor 80/70, raise-only | Vitest coverage floor, same numbers, raise-only |
| Enforcer (pinned, no SNAPSHOT) | `npm ci` with lockfile, exact versions, `npm audit` (high and above fails), licence allowlist |
| Trivy, SBOM, cosign | Same: image scan, CycloneDX SBOM from the lockfile, cosign |
| `check-deploy.sh`, overlays | Same script and layout |
| — | Bundle size budget; axe checks in component and e2e tests; Content-Security-Policy in the nginx config |

`npm run verify` = typecheck, lint, architecture rules, unit and component tests with coverage, build, bundle
budget. That one command is what the Stop hook, CI and the unattended runner call.

### Changes outside the new plugin
- **Runner (`factory-run.sh`):** today it hard-codes `./mvnw verify` and the Java protected files. Move both to a
  small per-project file so one runner serves both pipelines.
- **Java template:** publish the OpenAPI document (springdoc, or a checked-in `openapi.yaml` validated against
  the controllers) and attach it to each image/release, so the UI can pin a version of the contract.
- **Marketplace:** second entry; release tags `web-pipeline-vX.Y.Z`; its own changelog; `check-release-notes.sh`
  and `protect-repo.sh` learn the new component and tag pattern.

## Steps (one PR each, in this order)
| # | Step | Done when |
|---|---|---|
| F0 | Runner reads the verify command and protected paths from the project | Java templates behave as before; `test-factory-run.sh` covers a non-Maven project |
| F1 | `web-pipeline` skeleton template + its CI | Factory CI builds it: `npm ci`, `npm run verify`, image build and scan |
| F2 | Plugin: agents, `new-project`, `new-feature`, `intake`, hooks | `new-project` smoke test in factory CI; plugin validates; release tooling knows the component |
| F3 | Deploy: nginx image, overlays, deploy gate, CSP | kubeconform and `test-check-deploy.sh` pass on a generated UI project |
| F4 | Contract: OpenAPI from the Java template, generated client, drift check | A changed endpoint in the service fails the UI build until the client is regenerated |
| F5 | `add-oidc-login` skill | Login flow tested against a local stand-in issuer, as `add-resource-server` does |
| F6 | Acceptance | A real `factory:spec` → `factory:build` run on a fresh UI repo ends in a merged PR |

## Order relative to the queue
Recommended: finish **A5 (domain rules out of the agents)** before F2. Otherwise the new agents either copy the
banking checks or diverge from the Java ones on day one, and A5 has to be done twice. A4 (orchestrator split)
and A6 (evals) can come after; F0 and F1 don't depend on either.

## Risks and limits
- A cloud session can't run `npm`, so factory CI is the only check while building this, as with Maven. Steps
  that iterate on the template (F1, F3) go faster on the owner's machine.
- The unattended runner hasn't had its first real run yet (A2/A3 acceptance). Building a second pipeline on it
  before that run means any flaw is found twice.
- Visual quality can't be gated by tests alone. Screenshots from Playwright in the PR are the planned aid; the
  owner's eye is the gate.
- Two pipelines double the release and upgrade work until template drift has a maintenance agent (audit item,
  not yet queued).
