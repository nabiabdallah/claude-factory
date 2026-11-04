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
  `AUTH_AUDIENCE` (default `__SVC__`), expiry, and a usable `sub` (present, not blank, ≤ 255 chars, no control
  characters; per-caller rules depend on it). Without `AUTH_ISSUER_URI` the service does not start.
- Transport: the issuer is reached over https; plain http only to a loopback host as written (`localhost`,
  `127.x.y.z`, `[::1]`). Checked at startup and on every call (discovery and JWKS), so a discovery document
  can't move the key download to plain http.
- Default authorization: GET and HEAD need `SCOPE___SVC__:read`; all other methods `SCOPE___SVC__:write`.
- Fail closed: a blank audience refuses startup (Spring Boot would add no audience check for an empty list);
  calls to the issuer (discovery, JWKS) have 3s connect/read timeouts, so a stalled issuer gives 401, not hangs.
- Tests: a stand-in identity provider per test JVM (`TestJwtInitializer`: throwaway RSA key, OIDC discovery
  and JWKS on 127.0.0.1), so validation runs the production issuer-uri path; real signed tokens (`TestTokens`);
  `SecurityTest` proves 401 (missing, expired, foreign issuer, wrong audience, untrusted key), 403 (missing
  scope, no usable subject), 200 (right scope), HEAD = read, and open health; `StartupGuardsTest` proves no
  start without an issuer, with a blank issuer/audience or a plain-http issuer; `IdentityProviderTransportTest`
  proves the https/loopback rule and that the issuer client refuses plain http; `IdentityProviderTimeoutTest` proves a stalled issuer gives a fast 401.

## Alternatives considered
- **Opaque tokens with introspection** — a call to the issuer per request; JWT validation is local.
- **`jwt()` mock authentication in tests only** — skips signature/issuer/audience checks, so the real
  validation would be untested.
- **Method-level `@PreAuthorize` everywhere** — fine for per-endpoint refinements, but a URL/method default
  in one place is easier to review.

## Consequences
- Positive: secure by default; any IdP works by configuration; validation is tested end to end.
- Negative: clients need tokens with the right audience and scopes.
- Follow-ups: per-account authorization in each use case (caller from the token, checked first) and
  idempotency keys per caller; pick the IdP; rate limiting at the gateway.
