package __PKG__.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.simple.JdbcClient;

@PostgresTest
class PostgresSetupTest {

    @Autowired
    JdbcClient jdbc;

    @Test
    void flyway_migrations_ran_against_a_real_postgres() {
        assertThat(jdbc.sql("show server_version").query(String.class).single())
                .startsWith("18.");
        assertThat(jdbc.sql("select count(*) from flyway_schema_history where success")
                        .query(Integer.class)
                        .single())
                .isPositive();
    }

    @Test
    void numeric_round_trips_exactly_as_big_decimal() {
        var stored = jdbc.sql("select cast(:value as numeric(19, 2))")
                .param("value", new BigDecimal("1234567890.10"))
                .query(BigDecimal.class)
                .single();

        assertThat(stored).isEqualByComparingTo("1234567890.10").hasScaleOf(2);
    }
}
