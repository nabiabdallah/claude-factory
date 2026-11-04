package __PKG__.support;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.health.actuate.endpoint.HealthEndpointGroups;
import org.springframework.boot.test.context.SpringBootTest;

/** Readiness depends on the database; liveness does not (a DB outage must not restart pods). */
@SpringBootTest
class PostgresReadinessTest {

    @Autowired
    HealthEndpointGroups groups;

    @Test
    void readiness_includes_the_database_and_liveness_does_not() {
        assertThat(groups.get("readiness").isMember("db")).isTrue();
        assertThat(groups.get("liveness").isMember("db")).isFalse();
    }
}
