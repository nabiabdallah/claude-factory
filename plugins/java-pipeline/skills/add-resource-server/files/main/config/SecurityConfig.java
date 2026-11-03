package __PKG__.config;

import java.time.Duration;
import java.util.List;
import org.springframework.boot.autoconfigure.security.oauth2.resource.OAuth2ResourceServerProperties;
import org.springframework.boot.autoconfigure.security.oauth2.resource.servlet.JwkSetUriJwtDecoderBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.client.RestTemplate;

/**
 * OAuth2 resource server: every request needs a valid JWT (signature, issuer, audience, expiry; see
 * application.properties) except the Kubernetes health probes. Default rule: GET and HEAD need
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

    @Bean
    SecurityFilterChain api(HttpSecurity http, OAuth2ResourceServerProperties resourceServer) throws Exception {
        requireAudience(resourceServer.getJwt().getAudiences());
        return http.csrf(csrf -> csrf.disable()) // stateless API: no cookies, so no CSRF
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable())
                .logout(logout -> logout.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth.requestMatchers("/actuator/health", "/actuator/health/**")
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
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(IDENTITY_PROVIDER_TIMEOUT);
        requestFactory.setReadTimeout(IDENTITY_PROVIDER_TIMEOUT);
        var restOperations = new RestTemplate(requestFactory);
        return builder -> builder.restOperations(restOperations);
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
