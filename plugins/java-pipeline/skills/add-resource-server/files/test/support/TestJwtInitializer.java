package __PKG__.support;

import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.security.interfaces.RSAPublicKey;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.locks.LockSupport;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.core.env.MapPropertySource;

/**
 * A stand-in identity provider for tests, one per test JVM (registered in META-INF/spring.factories): a
 * throwaway RSA key and a local HTTP server on 127.0.0.1 serving the OIDC discovery document and the JWKS.
 * Every Spring test context points {@code issuer-uri} at it, so token validation runs the production path
 * (discovery, key download, signature, issuer, audience, expiry). {@link TestTokens} signs with the private
 * key. No key material is committed and no external network is used.
 */
public class TestJwtInitializer implements ApplicationContextInitializer<ConfigurableApplicationContext> {

    static final String KEY_ID = "test-key";

    private static KeyPair keys;
    private static String issuer;

    static synchronized KeyPair keys() {
        start();
        return keys;
    }

    static synchronized String issuer() {
        start();
        return issuer;
    }

    private static void start() {
        if (issuer != null) {
            return;
        }
        try {
            var generator = KeyPairGenerator.getInstance("RSA");
            generator.initialize(2048);
            keys = generator.generateKeyPair();
            var server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
            issuer = "http://127.0.0.1:" + server.getAddress().getPort();
            var jwks = new JWKSet(new RSAKey.Builder((RSAPublicKey) keys.getPublic())
                            .keyID(KEY_ID)
                            .build())
                    .toString(true);
            var discovery = """
                    {"issuer":"%s","jwks_uri":"%s/jwks","subject_types_supported":["public"],\
                    "response_types_supported":["code"],"id_token_signing_alg_values_supported":["RS256"]}""".formatted(issuer, issuer);
            server.createContext("/.well-known/openid-configuration", exchange -> respond(exchange, discovery));
            server.createContext("/jwks", exchange -> respond(exchange, jwks));
            // A pool of daemon threads: a stalled response (see stall()) must not block other requests, and the
            // server must not keep the JVM alive.
            server.setExecutor(Executors.newCachedThreadPool(runnable -> {
                var thread = new Thread(runnable, "test-identity-provider");
                thread.setDaemon(true);
                return thread;
            }));
            server.start();
            Runtime.getRuntime().addShutdownHook(new Thread(() -> server.stop(0)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("RSA is required by every Java platform", e);
        } catch (IOException e) {
            throw new UncheckedIOException("Could not start the test identity provider", e);
        }
    }

    private static volatile boolean stalled;

    /**
     * Makes the stand-in issuer stop answering (discovery and JWKS) until {@link #resume()}, to test that the
     * service doesn't hang on a slow or unreachable identity provider. Responses resume immediately on release.
     */
    public static void stall() {
        stalled = true;
    }

    public static void resume() {
        stalled = false;
    }

    private static void respond(HttpExchange exchange, String json) throws IOException {
        long deadline = System.nanoTime() + Duration.ofSeconds(60).toNanos();
        while (stalled && System.nanoTime() < deadline) {
            LockSupport.parkNanos(Duration.ofMillis(20).toNanos());
        }
        var body = json.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().add("Content-Type", "application/json");
        exchange.sendResponseHeaders(200, body.length);
        try (var out = exchange.getResponseBody()) {
            out.write(body);
        }
    }

    @Override
    public void initialize(ConfigurableApplicationContext context) {
        Map<String, Object> jwt = Map.of("spring.security.oauth2.resourceserver.jwt.issuer-uri", issuer());
        context.getEnvironment().getPropertySources().addFirst(new MapPropertySource("testIssuer", jwt));
    }
}
