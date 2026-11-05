# Changelog: java-pipeline

All notable changes to the plugin, newest first ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
[semver](https://semver.org/); before 1.0.0 a minor version may need action in projects: see **Upgrading**).
Each version is tagged `java-pipeline-vX.Y.Z`; projects pin the tag in `.claude/settings.json` (`ref`).
Decisions are in `docs/factory-adr/`.

## [0.16.0] - 2026-11-05

- New projects are pinned to the plugin version that created them: `new-project` writes
  `"ref": "java-pipeline-v<version>"` and `"sparsePaths": [".claude-plugin", "plugins"]` into the marketplace
  entry of `.claude/settings.json` (ADR 0015).
- This changelog, a factory-parent changelog, release tags with GitHub Releases, and `docs/ONBOARDING.md`.

**Upgrading:** projects created earlier follow `main`. Pin one by adding `"ref": "java-pipeline-v0.16.0"` to
`extraKnownMarketplaces.claude-factory.source` in its `.claude/settings.json`.

## [0.15.0] - 2026-11-05

- Templates: Actuator on its own management port 8081 (probes and `/actuator/prometheus` only); Prometheus
  metrics with latency histograms and URI templates; OpenTelemetry traces over OTLP (JDK sender), staging 100% /
  prod 10% sampling, raw URLs stripped from spans, trace ids in logs; NetworkPolicy opens metrics and OTLP only to
  `claude-factory/monitoring` namespaces (ADR 0014).
- add-resource-server permits `/actuator/prometheus` and requires the 0.15.0+ runtime tests.

**Upgrading:** probes and scrapers move to port `management` (8081). add-resource-server refuses projects
without the management port.

## [0.14.0] - 2026-11-05

- Templates on factory-parent 2.1.0: Maven Enforcer rules and a raise-only coverage floor (80% lines,
  70% branches); CI uploads the coverage report; `CLAUDE.md` and code-reviewer forbid weakening them (ADR 0013).
- Skeleton: two more `ErrorHandler` tests (it was below the branch floor).

**Upgrading:** a project below the floor or with a banned dependency fails on factory-parent 2.1.0: add tests or
drop the dependency.

## [0.13.0] - 2026-11-04

- Templates: `deploy/k8s` is base + `overlays/staging|prod` (pinned to commits on `main`, `newTag: unreleased`
  until promoted) + `components/recreate`; PodDisruptionBudget; default-deny NetworkPolicy (ADR 0012).
- `check-deploy.sh` and a `manifests` CI job: schemas, no mutable tags, the migration rollout rule on promotions.
- add-postgres: `MigrationRolloutTest` (risky DDL needs a `-- rollout:` header).
- Spec template Rollout section; reviewers check rollout compatibility.

**Upgrading:** deploy with `kubectl apply -k deploy/k8s/overlays/<env>`; promote by PR.

## [0.12.0] - 2026-11-04

- add-resource-server: https-only issuer (loopback http allowed), tokens need a usable `sub` (ADR 0011).
- Spec template Authorization section; reviewers and test-writer check caller isolation and per-caller
  idempotency keys.

## [0.11.0] - 2026-11-04

- Spring Boot 4.1 (factory-parent 2.0.0): templates and both add-* skills migrated (ADR 0010).

**Upgrading:** services on factory-parent 1.x need the code changes in ADR 0010's checklist.

## [0.10.0] - 2026-11-03

- Supply chain: digest-pinned base image (factory-parent 1.3.0), SBOM, Trivy image scan on every CI run,
  keyless cosign signing and SBOM attestation on `main`, Actions pinned to SHAs, pinned CI tools (ADR 0009).

## [0.9.1] - 2026-11-03

- add-resource-server hardened: blank audience refused, 3s identity-provider timeouts, HEAD needs the read scope;
  `StartupGuardsTest`, `IdentityProviderTimeoutTest`; exact 404/401 actuator cases.
- Template tests independent of test order.

## [0.9.0] - 2026-11-03

- add-resource-server skill: OAuth2 resource server with JWT (`AUTH_ISSUER_URI`, audience, scopes
  `<service>:read|write`), real signed test tokens from a local stand-in issuer (ADR 0008).

## [0.8.0] - 2026-11-03

- Container images with Jib on distroless (factory-parent 1.2.0), CI `image` job on `main`, Kustomize base for
  Kubernetes (ADR 0007).

## [0.7.0] - 2026-11-03

- Runtime basics: health probes only (no details), ECS JSON logs (plain text with the `local` profile),
  graceful shutdown (ADR 0006).

## [0.6.0] - 2026-11-03

- Dependabot for Maven and GitHub Actions in both templates (ADR 0005).

## [0.5.0] - 2026-11-03

- Lessons from the first persistence feature folded into the agents (concurrency tests that force overlap,
  mutation checks, PII in driver errors) and into add-postgres (`DbLocks`, lock timeout).

## [0.4.0] - 2026-11-03

- add-postgres skill: JdbcClient + Flyway, one transaction per use case, embedded Postgres for tests
  (factory-parent 1.1.0, ADR 0004).

## [0.3.0] - 2026-11-03

- Templates inherit factory-parent 1.0.0 from GitHub Packages (ADR 0003).

## [0.2.0] - 2026-11-03

- `templates/skeleton` is the default for new-project; the old template became `payments-example`;
  `--template` and `--list` (ADR 0002).

## [0.1.2] - 2026-11-02

- Spring context tests pass inside the Claude Code sandbox (Mockito as a Java agent, sandbox TMPDIR).

## [0.1.1] - 2026-11-02

- The template's settings reference the GitHub marketplace.

## [0.1.0] - 2026-11-02

- First version: architect-reviewer, test-writer and code-reviewer agents; new-feature, write-adr and new-project
  skills; Spotless and verify-gate hooks; the claude-factory marketplace (ADR 0001).
