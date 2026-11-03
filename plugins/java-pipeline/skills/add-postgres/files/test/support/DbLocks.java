package __PKG__.support;

import java.sql.Connection;
import java.sql.SQLException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.locks.LockSupport;
import javax.sql.DataSource;
import org.springframework.jdbc.core.simple.JdbcClient;

/**
 * Forces overlap in concurrency tests instead of relying on timing: hold a lock in the test's own
 * transaction, start the competing calls, wait until Postgres shows them blocked, then release.
 *
 * <pre>{@code
 * try (var held = DbLocks.hold(dataSource, "select id from account where id = ? for update", accountId)) {
 *     var first = pool.submit(() -> useCase.transfer(a));
 *     var second = pool.submit(() -> useCase.transfer(b));
 *     DbLocks.awaitLockWaiters(jdbc, 2, "select % from account % for update");
 * } // released: both proceed, one after the other
 * }</pre>
 */
public final class DbLocks {

    /** Safety net only: a test that waits this long has failed. */
    public static final Duration SAFETY_TIMEOUT = Duration.ofSeconds(30);

    private DbLocks() {}

    /** Locks held by the test in its own transaction until closed (then rolled back). */
    public static final class Held implements AutoCloseable {
        private final Connection connection;

        private Held(Connection connection) {
            this.connection = connection;
        }

        @Override
        public void close() {
            try {
                connection.rollback();
                connection.setAutoCommit(true);
                connection.close();
            } catch (SQLException e) {
                throw new IllegalStateException("Could not release test-held lock", e);
            }
        }
    }

    /** Runs {@code lockingSql} (e.g. {@code select … for update}) in a new transaction and keeps its locks. */
    public static Held hold(DataSource dataSource, String lockingSql, Object... params) throws SQLException {
        var connection = dataSource.getConnection();
        connection.setAutoCommit(false);
        try (var statement = connection.prepareStatement(lockingSql)) {
            for (int i = 0; i < params.length; i++) {
                statement.setObject(i + 1, params[i]);
            }
            statement.execute();
        } catch (SQLException e) {
            connection.rollback();
            connection.close();
            throw e;
        }
        return new Held(connection);
    }

    /**
     * Waits until at least {@code expected} other sessions wait on a heavyweight lock while running a
     * statement matching {@code queryLike} (SQL LIKE), so unrelated sessions can't satisfy the count.
     */
    public static void awaitLockWaiters(JdbcClient jdbc, int expected, String queryLike) {
        long deadline = System.nanoTime() + SAFETY_TIMEOUT.toNanos();
        int seen = 0;
        while (System.nanoTime() < deadline) {
            seen = jdbc.sql("select count(*) from pg_stat_activity where datname = current_database() "
                            + "and pid <> pg_backend_pid() and wait_event_type = 'Lock' and query like :pattern")
                    .param("pattern", queryLike)
                    .query(Integer.class)
                    .single();
            if (seen >= expected) {
                return;
            }
            LockSupport.parkNanos(Duration.ofMillis(10).toNanos());
        }
        throw new AssertionError(
                "Expected " + expected + " sessions waiting on a lock in '" + queryLike + "', saw " + seen);
    }

    /** All SQLStates along the cause chain (and SQLException next-chains), e.g. to assert no {@code 40P01}. */
    public static List<String> sqlStates(Throwable error) {
        var states = new ArrayList<String>();
        for (Throwable t = error; t != null; t = t.getCause()) {
            if (t instanceof SQLException sql) {
                for (SQLException s = sql; s != null; s = s.getNextException()) {
                    states.add(s.getSQLState());
                }
            }
        }
        return states;
    }
}
