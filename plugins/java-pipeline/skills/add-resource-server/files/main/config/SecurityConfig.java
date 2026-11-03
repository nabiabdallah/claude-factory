package __PKG__.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/**
 * OAuth2 resource server: every request needs a valid JWT (signature, issuer, audience, expiry; see
 * application.properties) except the Kubernetes health probes. Default rule: GET needs
 * {@value #READ}, everything else {@value #WRITE}; refine per endpoint here. Per-account rules
 * ("only your own account") belong in the use case, with the caller's subject passed in the command.
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    static final String READ = "SCOPE___SVC__:read";
    static final String WRITE = "SCOPE___SVC__:write";

    @Bean
    SecurityFilterChain api(HttpSecurity http) throws Exception {
        return http.csrf(csrf -> csrf.disable()) // stateless API: no cookies, so no CSRF
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable())
                .logout(logout -> logout.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth.requestMatchers("/actuator/health", "/actuator/health/**")
                        .permitAll()
                        .requestMatchers(HttpMethod.GET, "/**")
                        .hasAuthority(READ)
                        .anyRequest()
                        .hasAuthority(WRITE))
                .oauth2ResourceServer(resourceServer -> resourceServer.jwt(Customizer.withDefaults()))
                .build();
    }
}
