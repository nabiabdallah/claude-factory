/**
 * Postgres adapters: implement {@code application.port.out} repositories with {@code JdbcClient} and
 * explicit SQL, mapping rows to domain records here. The only package (with {@code config}) allowed to
 * use JDBC, SQL or Flyway types (enforced by ArchitectureTest). Construct adapters in {@code config};
 * test them with {@code @PostgresTest}.
 */
package __PKG__.adapter.out.persistence;
