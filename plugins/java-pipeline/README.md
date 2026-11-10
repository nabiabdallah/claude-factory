# java-pipeline

Claude Code plugin for Java 21 / Spring Boot hexagonal services. It runs a gated pipeline:
spec → plan → architect review → failing tests → implementation → `./mvnw verify` → code review.

- Skills: `/java-pipeline:new-feature`, `/java-pipeline:write-adr`, `/java-pipeline:new-project <name> <base.package> [--template <name>]`, `/java-pipeline:add-postgres` (Postgres + Flyway + `JdbcClient`, one transaction per use case, embedded Postgres for tests, a rollout header rule for risky migrations), `/java-pipeline:add-resource-server` (OAuth2 resource server: JWT from an https `AUTH_ISSUER_URI`, `sub` required, `<service>:read`/`write` scopes, real signed test tokens)
- Build rules come from `factory-parent` 2.1.0+ (Enforcer, coverage floor; factory ADR 0013); the code-reviewer flags attempts to weaken them
- Observability in the templates (0.15.0+, factory ADR 0014): Actuator on management port 8081 (probes, Prometheus), OpenTelemetry traces over OTLP without raw URLs
- Agents: `java-pipeline:architect-reviewer`, `java-pipeline:test-writer`, `java-pipeline:code-reviewer`
- Unattended runs (0.17.0+, factory ADR 0018): in a service repo, the label `factory:build` on an issue naming an approved spec runs `new-feature` in GitHub Actions (`factory-feature.yml` + `factory-run.sh` in the templates) and ends in a PR; the workflow, not the agent, checks the change, runs `./mvnw verify` and publishes
- Hooks: PostToolUse Spotless format of edited Java files; Stop gate running `./mvnw verify` (Maven projects only)
- Templates: `templates/skeleton` (default, empty) and `templates/payments-example`, copied by `new-project`, each with `deploy/k8s` staging/prod overlays and a promotion gate in CI (factory ADR 0012); add one by creating a directory with a `template.properties`
- `bin/mvnw-sandboxed`: on the Bash PATH while enabled; runs `./mvnw` with the Claude Code sandbox proxy so new dependencies download inside the sandbox (plain `./mvnw` outside it)

Requires `jq`, Java 21 and a project with `./mvnw`. See the marketplace README for install and update.
