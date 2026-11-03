# 0004. Persistence: Postgres via an add-postgres skill, JdbcClient, embedded Postgres for tests

- Status: Accepted
- Date: 2026-11-03
- Deciders: Noel Abi Abdallah

## Context
Services need a database, and agents must be able to run database tests themselves. Docker isn't
reachable from WSL here, and the Claude Code sandbox blocks Docker in any case; opening the Docker socket
to sandboxed commands would be root-equivalent and undo the sandbox. A spike showed that zonky
`embedded-postgres` (real Postgres 18 binaries from a jar) runs inside the sandbox once Unix sockets are
disabled (`unix_socket_directories=''`; their lock file would go to read-only `/tmp`).

## Decision
- **Delivery:** a `/java-pipeline:add-postgres` skill applies persistence to an existing service (new or
  old) with a script; the skeleton stays database-free. It refuses to overwrite files, doesn't commit, and
  doesn't edit `ArchitectureTest` (it prints the rule when missing).
- **Stack:** Postgres, Flyway, Spring `JdbcClient` with explicit SQL; no JPA.
- **Transactions:** one per use-case call, applied in `config/` with `TransactionalUseCases.wrap(...)`
  (Spring `TransactionInterceptor`), so `application/` stays Spring-free.
- **Tests:** an `ApplicationContextInitializer` (via `spring.factories`) starts one embedded Postgres per
  test JVM for every Spring test context; `@PostgresTest` = `@JdbcTest` on that database.
- **Structure:** both templates' `ArchitectureTest` gain `sql_only_in_persistence_adapters_and_config`
  (`java.sql`, `javax.sql`, Spring JDBC, Flyway only in `adapter.out.persistence` and `config`), which also
  closes the gap that `domain` could use `java.sql`.
- **Versions:** `factory-parent` 1.1.0 pins `embedded-postgres` and its binaries BOM.
- **Local runs:** `compose.yaml` with Postgres 18 bound to 127.0.0.1, started by the developer outside
  the sandbox; tests never need it.

## Alternatives considered
- **Testcontainers** — standard, but needs Docker: agents couldn't run database tests in the sandbox.
- **H2 (Postgres mode)** — not Postgres; behaviour differs in exactly the places that matter.
- **JPA/Hibernate** — less mapping code, but hides the SQL that runs.
- **`@Transactional` in services** — breaks the "no Spring in application" rule.
- **Database built into the skeleton** — every app would carry a database it may not need.

## Consequences
- Positive: real Postgres tests everywhere: laptop, sandbox, CI; exact `numeric` ↔ `BigDecimal`.
- Negative: embedded Postgres binaries add download size; one database per test JVM is shared across Spring
  test contexts.
- Negative: existing services need the ArchUnit rule added by hand.
- Follow-ups: locking/isolation for concurrent money movement; Testcontainers-based tests for other
  infrastructure (e.g. Kafka) would need a Docker decision of their own.
