package __PKG__.support;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.Map;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.core.env.MapPropertySource;

/**
 * Points every Spring test context at one real, embedded Postgres per test JVM (registered in
 * {@code src/test/resources/META-INF/spring.factories}). No Docker is needed, so it works on any
 * machine, in CI and inside the Claude Code sandbox.
 */
public class EmbeddedPostgresInitializer implements ApplicationContextInitializer<ConfigurableApplicationContext> {

    private static EmbeddedPostgres postgres;

    static synchronized EmbeddedPostgres postgres() {
        if (postgres == null) {
            try {
                postgres = EmbeddedPostgres.builder()
                        // TCP only: a Unix socket's lock file would go to /tmp, which is read-only in the sandbox.
                        .setServerConfig("unix_socket_directories", "")
                        .start();
            } catch (IOException e) {
                throw new UncheckedIOException("Could not start embedded Postgres", e);
            }
            var started = postgres;
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                try {
                    started.close();
                } catch (IOException ignored) {
                    // JVM is exiting; the data directory is temporary.
                }
            }));
        }
        return postgres;
    }

    @Override
    public void initialize(ConfigurableApplicationContext context) {
        var pg = postgres();
        Map<String, Object> datasource = Map.of(
                "spring.datasource.url", pg.getJdbcUrl("postgres", "postgres"),
                "spring.datasource.username", "postgres",
                "spring.datasource.password", "");
        context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("embeddedPostgres", datasource));
    }
}
