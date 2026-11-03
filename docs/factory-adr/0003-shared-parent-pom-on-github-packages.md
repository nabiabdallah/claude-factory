# 0003. Share the build through a factory-parent POM on GitHub Packages

- Status: Accepted
- Date: 2026-11-03
- Deciders: Noel Abi Abdallah

## Context
Every service was a copy of the template, including its whole Maven build (Java version, ArchUnit
and Spotless versions, the Spotless gate, the surefire Mockito agent). A build fix such as the
Mockito agent had to be patched into each service by hand, and the cost grows with every service.

## Decision
Move the shared build into `parents/factory-parent` (`io.github.nabiabdallah.factory:factory-parent`),
which inherits `spring-boot-starter-parent`. Templates, and therefore all new services, use it as
their parent and keep only coordinates and dependencies. It is published to GitHub Packages in the
`claude-factory` repo by `publish-parent.yml` when a tag `factory-parent-vX.Y.Z` matching the pom
version is pushed. Releases are immutable; there are no snapshots.

Services declare Maven Central first and the GitHub registry second, so only factory artifacts are
looked up there. GitHub's Maven registry is repository-scoped: a service repo's `GITHUB_TOKEN` cannot
read it, so each service repo has a secret `FACTORY_PACKAGES_TOKEN` (classic PAT, `read:packages`
only). Locally the same token sits in `~/.m2/settings.xml` (`<server id="github">`, mode 600).

## Alternatives considered
- **Template plus an upgrade skill** — no registry or credentials, but drift is managed by merging
  template diffs instead of removed.
- **Parent inside each repo** — doesn't share anything.
- **A public package** — no token needed to read, but publishes the factory's build to the world, and
  GitHub still documents a token requirement for Maven installs.

## Consequences
- Positive: a build fix ships to every service as a one-line version bump (Renovate can automate it).
- Positive: services' poms shrink to what is specific to them.
- Negative: a read token must exist locally and in every service repo. Agents running Maven inside the
  sandbox can read `~/.m2/settings.xml`, so they can read the token; its scope is limited to reading
  packages, and it can be revoked at any time.
- Negative: `maven.pkg.github.com` must be on the sandbox network allowlist.
- Follow-ups: a skill that creates the GitHub repo for a new service and sets `FACTORY_PACKAGES_TOKEN`;
  Renovate for parent bumps.
