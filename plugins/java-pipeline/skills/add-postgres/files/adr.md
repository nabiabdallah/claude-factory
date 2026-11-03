# __NUM__. Postgres with JdbcClient and Flyway; one transaction per use case

- Status: Accepted
- Date: __DATE__
- Deciders: Noel Abi Abdallah

## Context
The service needs durable storage. Domain and application code must stay framework-free (ArchitectureTest),
money must keep exact precision, and agents must be able to run database tests inside the Claude Code
sandbox, where Docker is not available.

## Decision
- **Database:** Postgres. Schema managed by Flyway migrations in `src/main/resources/db/migration/`;
  merged migrations are never edited.
- **Data access:** Spring's `JdbcClient` with explicit SQL, in adapters under `adapter/out/persistence/`
  that implement `application.port.out` interfaces and map rows to domain records. No JPA/Hibernate.
- **Transactions:** one per use-case call, applied in `config/` by wrapping the use-case bean with
  `TransactionalUseCases.wrap(...)` (Spring `TransactionInterceptor`, default propagation, rollback on any
  runtime exception). `application/` has no `@Transactional`.
- **Tests:** a real embedded Postgres (zonky embedded-postgres) for every Spring test context, started once
  per test JVM; `@PostgresTest` for repository adapters.
- **Structure:** ArchUnit rule `sql_only_in_persistence_adapters_and_config` keeps `java.sql`, `javax.sql`,
  Spring JDBC and Flyway out of every other package.

## Alternatives considered
- **JPA/Hibernate** — less mapping code, but lazy loading, dirty checking and entity/domain duplication hide
  what SQL runs; harder to review for a money-moving service.
- **`@Transactional` on application services** — idiomatic Spring, but puts Spring into `application/` and
  breaks the existing architecture rule.
- **Testcontainers** — the common choice, but needs Docker, which the sandbox blocks (opening the Docker
  socket to it would be root-equivalent); agents could not run database tests.
- **H2 in Postgres mode** — fast, but not Postgres; differences show up in production.

## Consequences
- Positive: SQL is explicit and reviewable; `numeric` ↔ `BigDecimal` is exact; agents run real database
  tests anywhere.
- Negative: hand-written row mapping; embedded Postgres binaries are larger than an H2 jar.
- Negative: Spring test contexts share one database per test JVM; tests outside `@PostgresTest` must not
  depend on an empty database.
- Follow-ups: decide isolation level and locking for concurrent money movements (e.g. `select ... for
  update` on debits) when the first such use case is persisted.
