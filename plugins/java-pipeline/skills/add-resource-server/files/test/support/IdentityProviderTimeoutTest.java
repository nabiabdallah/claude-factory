package __PKG__.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.annotation.DirtiesContext;

/**
 * A slow or unreachable identity provider must not hang requests or open the API: calls to it time out (3s,
 * SecurityConfig) and the request is refused with 401 while health stays up. Own context (nothing fetched yet),
 * real HTTP so filter-chain errors take the real error path.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "test.context=idp-timeout")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
class IdentityProviderTimeoutTest {

    private static final Duration BOUND = Duration.ofSeconds(20);

    @LocalServerPort
    int port;

    private final HttpClient http =
            HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    @AfterEach
    void resume() {
        TestJwtInitializer.resume();
    }

    private HttpResponse<String> get(String path, String authorization) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path)).timeout(BOUND);
        if (authorization != null) {
            request.header("Authorization", authorization);
        }
        return http.send(request.GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    @Test
    void a_stalled_identity_provider_gives_a_fast_401_and_health_stays_up() throws Exception {
        TestJwtInitializer.stall();
        var started = System.nanoTime();
        var pending = CompletableFuture.supplyAsync(() -> {
            try {
                return get("/security-probe", TestTokens.withScopes("__SVC__:read"));
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        });

        assertThat(get("/actuator/health/liveness", null).statusCode()).isEqualTo(200);

        var response = pending.get(BOUND.toSeconds(), TimeUnit.SECONDS);
        assertThat(response.statusCode()).as("refused, never served").isEqualTo(401);
        assertThat(Duration.ofNanos(System.nanoTime() - started)).isLessThan(Duration.ofSeconds(10));
    }
}
