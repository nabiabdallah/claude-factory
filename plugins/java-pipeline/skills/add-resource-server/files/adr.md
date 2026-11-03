# __NUM__. Protect the API as an OAuth2 resource server (JWT)

- Status: Accepted
- Date: __DATE__
- Deciders: Noel Abi Abdallah

## Context
The API must only serve authenticated callers with the right permissions. The identity provider is not
chosen yet, so the service must work with any OIDC/OAuth2 issuer, and tests must not need one.

## Decision
- Spring Security OAuth2 resource server with JWT. Every request needs a valid token except
  `/actuator/health/**` (Kubernetes probes). Stateless: no session, no cookies, CSRF off, no basic/form login.
- Token checks: signature against the issuer's published keys, issuer = `AUTH_ISSUER_URI`, audience =
  `AUTH_AUDIENCE` (default `__SVC__`), expiry. Without `AUTH_ISSUER_URI` the service does not start.
- Default authorization: GET needs `SCOPE___SVC__:read`; all other methods `SCOPE___SVC__:write`.
- Tests: a stand-in identity provider per test JVM (`TestJwtInitializer`: throwaway RSA key, OIDC discovery
  and JWKS on 127.0.0.1), so validation runs the production issuer-uri path; real signed tokens (`TestTokens`);
  `SecurityTest` proves 401 (missing, expired, foreign issuer, wrong audience, untrusted key), 403 (missing
  scope) and 200 (right scope), and that health needs no token.

## Alternatives considered
- **Opaque tokens with introspection** — a call to the issuer per request; JWT validation is local.
- **`jwt()` mock authentication in tests only** — skips signature/issuer/audience checks, so the real
  validation would be untested.
- **Method-level `@PreAuthorize` everywhere** — fine for per-endpoint refinements, but a URL/method default
  in one place is easier to review.

## Consequences
- Positive: secure by default; any IdP works by configuration; validation is tested end to end.
- Negative: clients need tokens with the right audience and scopes.
- Follow-ups: per-account authorization in each use case; pick the IdP; rate limiting at the gateway.
