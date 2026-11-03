-- Baseline. Add schema changes as new files: V2__create_customers.sql, V3__...
-- Never edit a migration once it is merged: Flyway's checksums would fail on every database that ran it.
-- Money columns are numeric(p, s) (BigDecimal in Java), never real or double precision.
select 1;
