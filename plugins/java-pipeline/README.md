# java-pipeline

Claude Code plugin for Java 21 / Spring Boot hexagonal services. It runs a gated pipeline:
spec → plan → architect review → failing tests → implementation → `./mvnw verify` → code review.

- Skills: `/java-pipeline:new-feature`, `/java-pipeline:write-adr`, `/java-pipeline:new-project <name> <base.package>`
- Agents: `java-pipeline:architect-reviewer`, `java-pipeline:test-writer`, `java-pipeline:code-reviewer`
- Hooks: PostToolUse Spotless format of edited Java files; Stop gate running `./mvnw verify` (Maven projects only)
- Template: `templates/spring-service`, copied by `new-project`
- `bin/mvnw-sandboxed`: on the Bash PATH while enabled; runs `./mvnw` with the Claude Code sandbox proxy so new dependencies download inside the sandbox (plain `./mvnw` outside it)

Requires `jq`, Java 21 and a project with `./mvnw`. See the marketplace README for install and update.
