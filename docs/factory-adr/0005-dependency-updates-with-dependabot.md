# 0005. Keep dependencies current with Dependabot

- Status: Accepted
- Date: 2026-11-03
- Deciders: Noel Abi Abdallah

## Context
The factory pins Spring Boot, plugin and GitHub Action versions in `factory-parent` and the templates, and
each service pins its `factory-parent` version. Without automation those versions age silently, including
security fixes. Renovate offers more control (shared presets, automerge) but needs a GitHub App install;
Dependabot is built into GitHub.

## Decision
- Dependabot, configured per repository in `.github/dependabot.yml`: the factory (parent, both templates,
  workflows) and every service (Maven incl. the `factory-parent` version, workflows). The templates carry
  the file, so new services get it.
- Weekly schedule; minor and patch updates grouped into one PR per ecosystem; majors one PR each.
  Commit prefixes `deps` (Maven) and `ci` (Actions).
- `factory-parent` comes from GitHub Packages, where Maven packages are repository-scoped, so each repo has
  a **Dependabot** secret `FACTORY_PACKAGES_TOKEN` (classic PAT, `read:packages` only). Dependabot secrets
  are separate from Actions secrets.
- Flow for the shared build: Dependabot bumps e.g. Spring Boot in `factory-parent` → merge → release a new
  parent (`factory-parent-vX.Y.Z` tag) → Dependabot opens a parent-version PR in every service.
- Every Dependabot PR goes through the same CI as human PRs; nothing auto-merges.

## Alternatives considered
- **Renovate** — grouping across repos and automerge rules, but an extra GitHub App with broad access.
- **Manual updates** — no tooling, but versions drift and security fixes are missed.

## Consequences
- Positive: weekly, reviewable, CI-tested update PRs everywhere; the parent bump reaches all services.
- Negative: one more secret per service repo; a parent release is still a manual tag.
- Negative: whether Dependabot finds workflows under the template folders (not the repo root) is not
  documented; verified on the first run.
