-- Baseline. Add schema changes as new files: V2__create_customers.sql, V3__...
-- Never edit a migration once it is merged: Flyway's checksums would fail on every database that ran it.
-- A migration the running version may not survive (drop, rename, type change, NOT NULL, new constraint) starts
-- with '-- rollout: compatible — <why>' or '-- rollout: recreate — <why>' (MigrationRolloutTest, check-deploy.sh).
-- Money columns are numeric(p, s) (BigDecimal in Java), never real or double precision.
select 1;
