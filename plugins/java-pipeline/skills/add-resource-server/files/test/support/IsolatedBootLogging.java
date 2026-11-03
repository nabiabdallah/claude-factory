package __PKG__.support;

import java.util.function.Supplier;

/**
 * Runs a {@code SpringApplication} started by a test itself (not by the Spring test framework) with Spring
 * Boot's logging system off. Spring Boot resets the JVM's logging configuration when such an application
 * fails to start or is closed, which would switch every later test context to plain-text logs and break
 * StructuredLoggingTest depending on test order. The logging system is chosen at startup and reused at
 * close, so it only needs to be off while {@code run()} executes.
 */
public final class IsolatedBootLogging {

    private static final String LOGGING_SYSTEM = "org.springframework.boot.logging.LoggingSystem";

    private IsolatedBootLogging() {}

    public static synchronized <T> T run(Supplier<T> startApplication) {
        var previous = System.getProperty(LOGGING_SYSTEM);
        System.setProperty(LOGGING_SYSTEM, "none");
        try {
            return startApplication.get();
        } finally {
            if (previous == null) {
                System.clearProperty(LOGGING_SYSTEM);
            } else {
                System.setProperty(LOGGING_SYSTEM, previous);
            }
        }
    }
}
