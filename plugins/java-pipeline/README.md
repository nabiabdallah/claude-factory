# java-pipeline

Claude Code plugin for Java 21 / Spring Boot hexagonal services. It runs a gated pipeline:
spec → plan → architect review → failing tests → implementation → `./mvnw verify` → code review.

- Skills: `/java-pipeline:new-feature`, `/java-pipeline:write-adr`, `/java-pipeline:new-project <name> <base.package> [--template <name>]`, `/java-pipeline:add-postgres` (Postgres + Flyway + `JdbcClient`, one transaction per use case, embedded Postgres for tests, a rollout header rule for risky migrations), `/java-pipeline:add-resource-server` (OAuth2 resource server: JWT from an https `AUTH_ISSUER_URI`, `sub` required, `<service>:read`/`write` scopes, real signed test tokens)
- Build rules come from `factory-parent` 2.1.0+ (Enforcer, coverage floor; factory ADR 0013); the code-reviewer flags attempts to weaken them
- Agents: `java-pipeline:architect-reviewer`, `java-pipeline:test-writer`, `java-pipeline:code-reviewer`
- Hooks: PostToolUse Spotless format of edited Java files; Stop gate running `./mvnw verify` (Maven projects only)
- Templates: `templates/skeleton` (default, empty) and `templates/payments-example`, copied by `new-project`, each with `deploy/k8s` staging/prod overlays and a promotion gate in CI (factory ADR 0012); add one by creating a directory with a `template.properties`
- `bin/mvnw-sandboxed`: on the Bash PATH while enabled; runs `./mvnw` with the Claude Code sandbox proxy so new dependencies download inside the sandbox (plain `./mvnw` outside it)

Requires `jq`, Java 21 and a project with `./mvnw`. See the marketplace README for install and update.
