package __PKG__.support;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import javax.sql.DataSource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** The helper itself: a test-held lock really blocks a competing statement, which proceeds after release. */
@PostgresTest
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class DbLocksTest {

    @Autowired
    JdbcClient jdbc;

    @Autowired
    DataSource dataSource;

    @BeforeEach
    void setUp() {
        jdbc.sql("create table if not exists lock_probe (id integer primary key, n integer not null)")
                .update();
        jdbc.sql("delete from lock_probe").update();
        jdbc.sql("insert into lock_probe (id, n) values (1, 0)").update();
    }

    @AfterEach
    void cleanUp() {
        jdbc.sql("drop table if exists lock_probe").update();
    }

    @Test
    void a_held_lock_blocks_a_competing_update_until_released() throws Exception {
        var pool = Executors.newSingleThreadExecutor();
        try {
            java.util.concurrent.Future<?> update;
            try (var held = DbLocks.hold(dataSource, "select id from lock_probe where id = ? for update", 1)) {
                update = pool.submit(() -> jdbc.sql("update lock_probe set n = n + 1 where id = 1").update());
                DbLocks.awaitLockWaiters(jdbc, 1, "update lock_probe %");
                assertThat(update.isDone()).as("update is blocked by the held lock").isFalse();
            }
            update.get(DbLocks.SAFETY_TIMEOUT.toSeconds(), TimeUnit.SECONDS);
            assertThat(jdbc.sql("select n from lock_probe where id = 1").query(Integer.class).single())
                    .isEqualTo(1);
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void sql_states_are_collected_from_the_cause_chain() {
        var error = catchThrowable(() -> jdbc.sql("insert into lock_probe (id, n) values (1, 0)").update());

        assertThat(DbLocks.sqlStates(error)).contains("23505");
    }
}
