package __PKG__.support;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;

/**
 * Real signed JWTs for tests, validated by the service's normal token checks. Use as the Authorization header:
 *
 * <pre>{@code
 * mvc.perform(get("/things").header("Authorization", TestTokens.withScopes("__SVC__:read")))
 * }</pre>
 */
public final class TestTokens {

    public static final String AUDIENCE = "__SVC__";
    public static final String SUBJECT = "test-user";

    private TestTokens() {}

    /** {@code Bearer <jwt>} with the given scopes, valid for this service. */
    public static String withScopes(String... scopes) {
        return token().scopes(scopes).bearer();
    }

    public static Builder token() {
        return new Builder();
    }

    public static final class Builder {
        private String issuer = TestJwtInitializer.issuer();
        private String audience = AUDIENCE;
        private String subject = SUBJECT;
        private String scope = "";
        private Instant expiresAt = Instant.now().plus(Duration.ofMinutes(5));
        private PrivateKey signingKey = TestJwtInitializer.keys().getPrivate();

        public Builder scopes(String... scopes) {
            this.scope = String.join(" ", scopes);
            return this;
        }

        public Builder issuer(String issuer) {
            this.issuer = issuer;
            return this;
        }

        public Builder audience(String audience) {
            this.audience = audience;
            return this;
        }

        public Builder subject(String subject) {
            this.subject = subject;
            return this;
        }

        public Builder expiresAt(Instant expiresAt) {
            this.expiresAt = expiresAt;
            return this;
        }

        /** Signs with a key the service doesn't trust. */
        public Builder signedByAnotherKey() {
            try {
                var generator = KeyPairGenerator.getInstance("RSA");
                generator.initialize(2048);
                this.signingKey = generator.generateKeyPair().getPrivate();
            } catch (NoSuchAlgorithmException e) {
                throw new IllegalStateException(e);
            }
            return this;
        }

        public String bearer() {
            var now = Instant.now();
            var claims = new JWTClaimsSet.Builder()
                    .issuer(issuer)
                    .audience(audience)
                    .subject(subject)
                    .issueTime(Date.from(now.minusSeconds(5)))
                    .expirationTime(Date.from(expiresAt))
                    .claim("scope", scope)
                    .build();
            var header = new JWSHeader.Builder(JWSAlgorithm.RS256)
                    .keyID(TestJwtInitializer.KEY_ID)
                    .build();
            var jwt = new SignedJWT(header, claims);
            try {
                jwt.sign(new RSASSASigner(signingKey));
            } catch (JOSEException e) {
                throw new IllegalStateException("Could not sign test token", e);
            }
            return "Bearer " + jwt.serialize();
        }
    }
}
