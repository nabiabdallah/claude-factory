package __PKG__.support;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.head;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

/** The token checks and the default scope rule, through the real filter chain and a real JWT decoder. */
@SpringBootTest
@AutoConfigureMockMvc
class SecurityTest {

    private static final String READ = "__SVC__:read";
    private static final String WRITE = "__SVC__:write";

    @Autowired
    MockMvc mvc;

    @Test
    void health_probes_need_no_token() throws Exception {
        mvc.perform(get("/actuator/health/liveness")).andExpect(status().isOk());
        mvc.perform(get("/actuator/health/readiness")).andExpect(status().isOk());
    }

    @Test
    void no_token_is_401() throws Exception {
        mvc.perform(get("/security-probe")).andExpect(status().isUnauthorized());
        mvc.perform(post("/security-probe")).andExpect(status().isUnauthorized());
    }

    @Test
    void expired_token_is_401() throws Exception {
        var expired = TestTokens.token()
                .scopes(READ)
                .expiresAt(Instant.now().minusSeconds(300))
                .bearer();
        mvc.perform(get("/security-probe").header("Authorization", expired)).andExpect(status().isUnauthorized());
    }

    @Test
    void token_from_another_issuer_is_401() throws Exception {
        var foreign =
                TestTokens.token().scopes(READ).issuer("https://evil.test.invalid").bearer();
        mvc.perform(get("/security-probe").header("Authorization", foreign)).andExpect(status().isUnauthorized());
    }

    @Test
    void token_for_another_audience_is_401() throws Exception {
        var otherService =
                TestTokens.token().scopes(READ).audience("another-service").bearer();
        mvc.perform(get("/security-probe").header("Authorization", otherService))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void token_signed_with_an_untrusted_key_is_401() throws Exception {
        var forged = TestTokens.token().scopes(READ).signedByAnotherKey().bearer();
        mvc.perform(get("/security-probe").header("Authorization", forged)).andExpect(status().isUnauthorized());
    }

    @Test
    void valid_token_without_the_needed_scope_is_403() throws Exception {
        mvc.perform(get("/security-probe").header("Authorization", TestTokens.withScopes("unrelated:scope")))
                .andExpect(status().isForbidden());
        mvc.perform(post("/security-probe").header("Authorization", TestTokens.withScopes(READ)))
                .andExpect(status().isForbidden());
    }

    @Test
    void read_scope_allows_get_and_write_scope_allows_post() throws Exception {
        mvc.perform(get("/security-probe").header("Authorization", TestTokens.withScopes(READ)))
                .andExpect(status().isOk())
                .andExpect(content().string("read-ok"));
        mvc.perform(post("/security-probe").header("Authorization", TestTokens.withScopes(WRITE)))
                .andExpect(status().isOk())
                .andExpect(content().string("write-ok"));
    }

    @Test
    void head_needs_the_read_scope_like_get() throws Exception {
        mvc.perform(head("/security-probe").header("Authorization", TestTokens.withScopes(READ)))
                .andExpect(status().isOk());
        mvc.perform(head("/security-probe").header("Authorization", TestTokens.withScopes(WRITE)))
                .andExpect(status().isForbidden());
    }

    @Test
    void token_without_a_usable_subject_is_401() throws Exception {
        for (var subject : new String[] {null, "", "   ", "a".repeat(256), "user\u0000admin", "user\nadmin"}) {
            var token = TestTokens.token().scopes(READ).subject(subject).bearer();
            mvc.perform(get("/security-probe").header("Authorization", token))
                    .andExpect(status().isUnauthorized());
        }
    }

    @Test
    void subject_up_to_255_characters_is_accepted() throws Exception {
        var token = TestTokens.token().scopes(READ).subject("a".repeat(255)).bearer();
        mvc.perform(get("/security-probe").header("Authorization", token)).andExpect(status().isOk());
    }
}
