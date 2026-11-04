package __PKG__.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.IOException;
import java.net.URI;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.web.client.ResourceAccessException;

/**
 * Tokens are only as trustworthy as the keys they are checked against: the identity provider is reached over
 * https, or over plain http only on this machine (loopback, e.g. a local Keycloak or the tests' stand-in). The
 * rule is checked on the host as written, never by resolving it.
 */
class IdentityProviderTransportTest {

    @ParameterizedTest
    @ValueSource(
            strings = {
                "https://idp.example.com/realms/main",
                "HTTPS://idp.example.com",
                "http://localhost:8080/realms/main",
                "http://LOCALHOST",
                "http://127.0.0.1:9000",
                "http://127.10.0.255/x",
                "http://[::1]:8080",
                "http://[0:0:0:0:0:0:0:1]"
            })
    void https_anywhere_and_plain_http_on_loopback_are_accepted(String uri) {
        assertThat(SecurityConfig.isHttpsOrLoopback(URI.create(uri))).isTrue();
    }

    @ParameterizedTest
    @ValueSource(
            strings = {
                "http://idp.example.com",
                "HTTP://idp.example.com",
                "http://127.0.0.1.evil.example",
                "http://localhost.evil.example",
                "http://127.0.0.1@evil.example",
                "http://128.0.0.1",
                "http://127.0.0.256",
                "http://127.1",
                "http://0.0.0.0",
                "http://[::2]",
                "ftp://idp.example.com",
                "https:///no-host",
                "idp.example.com"
            })
    void anything_else_is_refused(String uri) {
        assertThat(SecurityConfig.isHttpsOrLoopback(URI.create(uri))).isFalse();
    }

    /** Covers a discovery document whose jwks_uri points to plain http on another host. */
    @Test
    void the_identity_provider_client_refuses_plain_http_to_another_host_before_connecting() {
        var client = SecurityConfig.identityProviderClient();
        assertThatThrownBy(() -> client.getForObject("http://jwks.invalid/jwks", String.class))
                .isInstanceOf(ResourceAccessException.class)
                .rootCause()
                .isInstanceOf(IOException.class)
                .hasMessageContaining("must use https");
    }

    @Test
    void the_identity_provider_client_lets_loopback_http_through() {
        var client = SecurityConfig.identityProviderClient();
        // Port 9 (discard) is closed on build machines: the call is attempted and fails to connect.
        assertThatThrownBy(() -> client.getForObject("http://127.0.0.1:9/jwks", String.class))
                .isInstanceOf(ResourceAccessException.class)
                .rootCause()
                .satisfies(cause -> assertThat(String.valueOf(cause.getMessage())).doesNotContain("must use https"));
    }
}
