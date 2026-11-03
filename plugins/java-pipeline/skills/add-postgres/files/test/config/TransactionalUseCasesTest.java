package __PKG__.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import __PKG__.support.PostgresTest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** Real commits and rollbacks, so the test's own transaction is switched off. */
@PostgresTest
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class TransactionalUseCasesTest {

    interface RecordValue {
        void record(String value, boolean failAfterWriting);
    }

    static class NotAPort implements RecordValue {
        @Override
        public void record(String value, boolean failAfterWriting) {}
    }

    @Autowired
    JdbcClient jdbc;

    @Autowired
    PlatformTransactionManager transactionManager;

    RecordValue useCase;

    @BeforeEach
    void setUp() {
        jdbc.sql("create table if not exists tx_probe (value text not null)").update();
        jdbc.sql("delete from tx_probe").update();
        RecordValue plain = (value, failAfterWriting) -> {
            jdbc.sql("insert into tx_probe (value) values (:value)")
                    .param("value", value)
                    .update();
            if (failAfterWriting) {
                throw new IllegalStateException("use case failed after writing");
            }
        };
        useCase = TransactionalUseCases.wrap(RecordValue.class, plain, transactionManager);
    }

    @Test
    void commits_when_the_use_case_returns() {
        useCase.record("kept", false);

        assertThat(rows()).isEqualTo(1);
    }

    @Test
    void rolls_back_everything_when_the_use_case_throws() {
        assertThatThrownBy(() -> useCase.record("discarded", true)).isInstanceOf(IllegalStateException.class);

        assertThat(rows()).isZero();
    }

    @Test
    void only_accepts_an_interface_as_the_port() {
        assertThatThrownBy(() -> TransactionalUseCases.wrap(NotAPort.class, new NotAPort(), transactionManager))
                .isInstanceOf(IllegalArgumentException.class);
    }

    private int rows() {
        return jdbc.sql("select count(*) from tx_probe").query(Integer.class).single();
    }
}
