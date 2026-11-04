package __PKG__.support;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import __PKG__.__APP__;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.core.io.support.SpringFactoriesLoader;

/**
 * The service fails closed: it refuses to start without an issuer, with a blank issuer, with an issuer reached
 * over plain http on another host, or with a blank audience (an empty audience list would switch Spring Boot's
 * audience check off). The application is started
 * by hand with the project's registered initializers, optionally without the test issuer.
 */
class StartupGuardsTest {

    private static List<ApplicationContextInitializer<?>> initializers(boolean withTestIssuer) {
        var all = new ArrayList<ApplicationContextInitializer<?>>();
        for (var initializer : SpringFactoriesLoader.loadFactories(
                ApplicationContextInitializer.class, StartupGuardsTest.class.getClassLoader())) {
            if (withTestIssuer || !(initializer instanceof TestJwtInitializer)) {
                all.add(initializer);
            }
        }
        return all;
    }

    private static void start(boolean withTestIssuer, String... extraArgs) {
        var args = new ArrayList<>(List.of("--server.port=0", "--spring.main.banner-mode=off"));
        args.addAll(List.of(extraArgs));
        var app = new SpringApplication(__APP__.class);
        app.setInitializers(initializers(withTestIssuer));
        ConfigurableApplicationContext ctx = null;
        try {
            ctx = IsolatedBootLogging.run(() -> app.run(args.toArray(String[]::new)));
        } finally {
            if (ctx != null) {
                ctx.close(); // a wrongly started context must not leak into other tests
            }
        }
    }

    private static void assumeNoIssuerInTheEnvironment() {
        assumeTrue(System.getenv("AUTH_ISSUER_URI") == null, "AUTH_ISSUER_URI is set in this environment");
        assumeTrue(System.getProperty("AUTH_ISSUER_URI") == null, "AUTH_ISSUER_URI is set as a system property");
    }

    @Test
    void does_not_start_without_an_issuer_and_the_error_names_it() {
        assumeNoIssuerInTheEnvironment();
        assertThatThrownBy(() -> start(false)).satisfies(e -> {
            var chain = new StringBuilder();
            for (Throwable t = e; t != null; t = t.getCause()) {
                chain.append(t.getMessage()).append('\n');
            }
            assertThat(chain.toString()).contains("AUTH_ISSUER_URI");
        });
    }

    @Test
    void does_not_start_with_a_blank_issuer() {
        assumeNoIssuerInTheEnvironment();
        assertThatThrownBy(() -> start(false, "--spring.security.oauth2.resourceserver.jwt.issuer-uri="))
                .hasRootCauseInstanceOf(org.springframework.beans.factory.NoSuchBeanDefinitionException.class)
                .rootCause()
                .hasMessageContaining("org.springframework.security.oauth2.jwt.JwtDecoder");
    }

    @Test
    void does_not_start_with_a_blank_audience() {
        assertThatThrownBy(() -> start(true, "--AUTH_AUDIENCE="))
                .rootCause()
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("audience");
    }

    @Test
    void does_not_start_with_a_plain_http_issuer_and_does_not_echo_credentials() {
        assertThatThrownBy(() -> start(
                        false, "--spring.security.oauth2.resourceserver.jwt.issuer-uri=http://user:s3cret@idp.example"))
                .satisfies(e -> {
                    var chain = new StringBuilder();
                    for (Throwable t = e; t != null; t = t.getCause()) {
                        chain.append(t.getMessage()).append('\n');
                    }
                    assertThat(chain.toString())
                            .contains("AUTH_ISSUER_URI", "https", "idp.example")
                            .doesNotContain("s3cret");
                });
    }

    @Test
    void starts_with_an_https_issuer() {
        // The issuer is contacted on the first request, not at startup: an unreachable https issuer still starts.
        assertThatCode(() -> start(false, "--spring.security.oauth2.resourceserver.jwt.issuer-uri=https://idp.invalid"))
                .doesNotThrowAnyException();
    }
}
