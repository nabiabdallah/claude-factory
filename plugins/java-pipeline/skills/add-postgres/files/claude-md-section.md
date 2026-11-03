
## Persistence (Postgres)
- Data access: `JdbcClient` with explicit SQL in `adapter/out/persistence/`; map rows to domain records there. No JPA.
- Schema: Flyway migrations in `src/main/resources/db/migration/` (`V<n>__<description>.sql`). Never edit a
  merged migration; add a new one.
- Amounts: `numeric(p, s)` columns ↔ `BigDecimal`. Never `real` / `double precision` for money.
- Transactions: one per use-case call. Wrap the use-case bean in `config/` with
  `TransactionalUseCases.wrap(Port.class, new SomeService(...), transactionManager)`. No `@Transactional` in `application/`.
- Repository tests: `@PostgresTest` (real embedded Postgres + Flyway, rolled back per test); construct the adapter
  with the injected `JdbcClient`. Every `@SpringBootTest` also runs against the embedded database.
- Local run: `docker compose up -d` (you, outside the sandbox), then `./mvnw spring-boot:run`.
