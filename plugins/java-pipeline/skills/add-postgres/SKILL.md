---
name: add-postgres
description: Add Postgres persistence to the current java-pipeline service — JdbcClient + Flyway, one transaction per use case, and a real embedded Postgres for tests (no Docker; works in the sandbox). Use when the user asks to add a database, Postgres, persistence or storage to a service.
disable-model-invocation: true
---

# Add Postgres

1. Confirm you are in the service's root (it has `pom.xml` inheriting `factory-parent`) and the working
   tree is clean (`git status`). If not, stop and tell the user.
2. Create a branch, e.g. `git switch -c build/add-postgres`.
3. Run the script exactly once from the project root:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/add-postgres/scripts/add-postgres.sh"
   ```

   It adds the dependencies (and bumps `factory-parent` to at least 1.1.0), `db/migration/V1__baseline.sql`,
   `adapter/out/persistence/`, `config/TransactionalUseCases`, test support (`@PostgresTest`, embedded
   Postgres for every Spring test context), datasource properties, `compose.yaml`, a `CLAUDE.md` section
   and an ADR, then runs `./mvnw verify`. It refuses to overwrite existing files and does not commit.
4. If it fails, report its output verbatim. Do not weaken `ArchitectureTest` or delete tests.
5. If it printed an ArchitectureTest rule, show it to the user: they add it themselves (agents may not
   edit `ArchitectureTest`).
6. Show the user `git status` and a summary of the diff. Commit only when they agree, staging files by
   path (never `git add -A`).
7. Next step for the user: move an in-memory adapter to Postgres with `/java-pipeline:new-feature`.
