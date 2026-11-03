package __PKG__.support;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;

/**
 * Repository-adapter test against the embedded Postgres: JDBC, {@code JdbcClient}, Flyway migrations and a
 * transaction manager, no web layer. Each test runs in a transaction that is rolled back. Inject
 * {@code JdbcClient} and construct the adapter under test with it.
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@JdbcTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
public @interface PostgresTest {}
