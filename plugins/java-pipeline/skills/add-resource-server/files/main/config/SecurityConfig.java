package __PKG__.config;

import java.io.IOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;
import org.springframework.boot.security.oauth2.server.resource.autoconfigure.OAuth2ResourceServerProperties;
import org.springframework.boot.security.oauth2.server.resource.autoconfigure.JwkSetUriJwtDecoderBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.client.RestTemplate;

/**
 * OAuth2 resource server: every request needs a valid JWT (signature, issuer, audience, expiry; see
 * application.properties) and a usable subject, except the Kubernetes health probes. Default rule: GET and HEAD need
 * {@value #READ}, everything else {@value #WRITE}; refine per endpoint here. Per-account rules
 * ("only your own account") belong in the use case, with the caller's subject passed in the command.
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    static final String READ = "SCOPE___SVC__:read";
    static final String WRITE = "SCOPE___SVC__:write";

    /** Upper bound for each call to the identity provider (OIDC discovery, JWKS); spec 0004 failure modes. */
    static final Duration IDENTITY_PROVIDER_TIMEOUT = Duration.ofSeconds(3);

    /** Longest accepted {@code sub}: callers' subjects are stored (ownership, idempotency keys). */
    static final int MAX_SUBJECT_LENGTH = 255;

    private static final Pattern LOOPBACK_IPV4 =
            Pattern.compile("127\\.(25[0-5]|2[0-4]\\d|1?\\d?\\d)\\.(25[0-5]|2[0-4]\\d|1?\\d?\\d)\\.(25[0-5]|2[0-4]\\d|1?\\d?\\d)");

    @Bean
    SecurityFilterChain api(HttpSecurity http, OAuth2ResourceServerProperties resourceServer) throws Exception {
        requireAudience(resourceServer.getJwt().getAudiences());
        requireSecureIssuer(resourceServer.getJwt().getIssuerUri());
        return http.csrf(csrf -> csrf.disable()) // stateless API: no cookies, so no CSRF
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable())
                .logout(logout -> logout.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                // Probes and Prometheus need no token. Actuator is served only on the management port (factory
                // ADR 0014), which the NetworkPolicy opens to the monitoring namespace alone.
                .authorizeHttpRequests(auth -> auth.requestMatchers(
                                "/actuator/health", "/actuator/health/**", "/actuator/prometheus")
                        .permitAll()
                        .requestMatchers(HttpMethod.GET, "/**")
                        .hasAuthority(READ)
                        .requestMatchers(HttpMethod.HEAD, "/**")
                        .hasAuthority(READ)
                        .anyRequest()
                        .hasAuthority(WRITE))
                .oauth2ResourceServer(server -> server.jwt(Customizer.withDefaults()))
                .build();
    }

    /**
     * Calls to the identity provider get connect and read timeouts, so a slow or unreachable provider fails
     * requests fast instead of hanging them (and every server thread). Used for discovery and the JWKS.
     */
    @Bean
    JwkSetUriJwtDecoderBuilderCustomizer identityProviderTimeouts() {
        var restOperations = identityProviderClient();
        return builder -> builder.restOperations(restOperations);
    }

    /**
     * The client for every call to the identity provider: timeouts, and https only (plain http to loopback), checked
     * per request, so a discovery document can't move the key download to plain http. HttpURLConnection does not
     * follow redirects from https to http.
     */
    static RestTemplate identityProviderClient() {
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(IDENTITY_PROVIDER_TIMEOUT);
        requestFactory.setReadTimeout(IDENTITY_PROVIDER_TIMEOUT);
        var client = new RestTemplate(requestFactory);
        client.getInterceptors().add((request, body, execution) -> {
            if (!isHttpsOrLoopback(request.getURI())) {
                throw new IOException(
                        "Refused call to the identity provider at " + describe(request.getURI()) + ": it must use https");
            }
            return execution.execute(request, body);
        });
        return client;
    }

    /**
     * Tokens are rejected unless {@code sub} names the caller: present, not blank, at most
     * {@value #MAX_SUBJECT_LENGTH} characters, no control characters. Per-caller rules (ownership, idempotency
     * keys) depend on it. Spring Boot adds this validator to the token checks.
     */
    @Bean
    OAuth2TokenValidator<Jwt> subjectValidator() {
        var invalid = OAuth2TokenValidatorResult.failure(
                new OAuth2Error("invalid_token", "The token has no usable subject (sub)", null));
        return jwt -> jwt.getClaims().get("sub") instanceof String subject
                        && !subject.isBlank()
                        && subject.length() <= MAX_SUBJECT_LENGTH
                        && subject.chars().noneMatch(Character::isISOControl)
                ? OAuth2TokenValidatorResult.success()
                : invalid;
    }

    /**
     * https, or plain http to a loopback host written as such ({@code localhost}, {@code 127.x.y.z},
     * {@code [::1]}). The host is never resolved: a name that resolves to loopback here may not elsewhere.
     */
    static boolean isHttpsOrLoopback(URI uri) {
        var scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
        var host = uri.getHost() == null ? "" : uri.getHost().toLowerCase(Locale.ROOT);
        if (host.isEmpty()) {
            return false;
        }
        if (scheme.equals("https")) {
            return true;
        }
        return scheme.equals("http")
                && (host.equals("localhost")
                        || host.equals("[::1]")
                        || host.equals("[0:0:0:0:0:0:0:1]")
                        || LOOPBACK_IPV4.matcher(host).matches());
    }

    /** Scheme, host and port only: an issuer URI may carry credentials. */
    private static String describe(URI uri) {
        return uri.getScheme() + "://" + uri.getHost() + (uri.getPort() == -1 ? "" : ":" + uri.getPort());
    }

    /** Fails startup when the configured issuer would be reached without TLS. Blank: no JwtDecoder, no start. */
    private static void requireSecureIssuer(String issuer) {
        if (issuer == null || issuer.isBlank()) {
            return;
        }
        URI uri;
        try {
            uri = new URI(issuer);
        } catch (URISyntaxException e) {
            // Not chained: the exception message would repeat the value, credentials included.
            throw new IllegalStateException("AUTH_ISSUER_URI is not a valid URI. Refusing to start");
        }
        if (!isHttpsOrLoopback(uri)) {
            throw new IllegalStateException("AUTH_ISSUER_URI must use https (plain http only to localhost, 127.x.y.z"
                    + " or [::1]); got " + describe(uri) + ". Refusing to start");
        }
    }

    /**
     * Spring Boot adds no audience check when the audience list is empty, e.g. when AUTH_AUDIENCE is set but
     * blank (the default only applies when it is absent). That would accept tokens issued for any service, so
     * refuse to start instead.
     */
    private static void requireAudience(List<String> audiences) {
        if (audiences == null || audiences.isEmpty() || audiences.stream().anyMatch(a -> a == null || a.isBlank())) {
            throw new IllegalStateException(
                    "No token audience configured (AUTH_AUDIENCE is blank): refusing to start without an audience check");
        }
    }
}
