
## Persistence (Postgres)
- Data access: `JdbcClient` with explicit SQL in `adapter/out/persistence/`; map rows to domain records there. No JPA.
- Schema: Flyway migrations in `src/main/resources/db/migration/` (`V<n>__<description>.sql`). Never edit a
  merged migration; add a new one.
- Rollout: during a rolling update the previous version runs against the new schema. Prefer expand/contract
  (add → migrate → stop using → drop in a later release). A migration with a drop, rename, type change,
  `SET NOT NULL`, NOT NULL column without default, or new constraint/unique index must start with
  `-- rollout: compatible — <why>` or `-- rollout: recreate — <why>` (`MigrationRolloutTest` fails otherwise).
  `recreate` means downtime: the promotion that crosses it must add `deploy/k8s/components/recreate` to the
  overlay (`.github/scripts/check-deploy.sh` enforces it). Ask the user before choosing `recreate`.
- Amounts: `numeric(p, s)` columns ↔ `BigDecimal`. Never `real` / `double precision` for money.
- Read stored amounts without rounding (`setScale(currencyScale, RoundingMode.UNNECESSARY)`, error if it
  doesn't fit); reject request amounts with more decimals than the currency allows (400), never round them.
- Transactions: one per use-case call. Wrap the use-case bean in `config/` with
  `TransactionalUseCases.wrap(Port.class, new SomeService(...), transactionManager)`. No `@Transactional` in `application/`.
- Concurrency tests force the overlap with `support/DbLocks` (test-held lock + `awaitLockWaiters` scoped to
  the statement), never timing; assert deadlock-freedom as "no SQLState 40P01".
- Repository tests: `@PostgresTest` (real embedded Postgres + Flyway, rolled back per test); construct the adapter
  with the injected `JdbcClient`. Every `@SpringBootTest` also runs against the embedded database.
- Local run: `docker compose up -d` (you, outside the sandbox), then `./mvnw spring-boot:run`.
