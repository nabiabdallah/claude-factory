# 0008. Auth as a skill: OAuth2 resource server with real signed test tokens

- Status: Accepted
- Date: 2026-11-03
- Deciders: Noel Abi Abdallah

## Context
Services must only serve authenticated, authorized callers. The identity provider isn't chosen yet (owner:
IdP-agnostic). Existing services have endpoint tests without tokens, so adding auth is a migration, not a
template default.

## Decision
- A `/java-pipeline:add-resource-server` skill (script) adds Spring Security's OAuth2 resource server:
  all requests need a valid JWT except `/actuator/health/**`; stateless; CSRF, basic and form login off.
- Validation: issuer-uri `AUTH_ISSUER_URI` (discovery + JWKS: signature and issuer), audience `AUTH_AUDIENCE`
  (default: service name), expiry. No `AUTH_ISSUER_URI` → the service doesn't start.
- Default authorization: GET → `SCOPE_<service>:read`, other methods → `SCOPE_<service>:write`.
- Tests: `TestJwtInitializer` runs a stand-in identity provider per test JVM on 127.0.0.1 (throwaway RSA
  key, OIDC discovery, JWKS), so tests exercise the production issuer-uri path; `TestTokens` signs real
  tokens. `SecurityTest` covers 401 (missing, expired, foreign issuer, wrong audience, untrusted key), 403
  (missing scope, read-only POST), 200 and open health probes. Mutation-checked: permit-all, no audience
  check and no scope rules each fail it.
- Templates' Actuator test accepts exactly 401 or 404 for unexposed endpoints (the security filter answers
  first), rather than opening `/actuator/**`.

## Alternatives considered
- **Auth in the skeleton by default** — every new app secure from day one, but tests and local runs need an
  issuer from the start and existing services still need the migration; kept as an explicit step.
- **`public-key-location` in tests** — Spring Boot ignores it once `issuer-uri` is set, so the production
  path wouldn't be tested.
- **Mock authentication (`jwt()`) only** — skips signature, issuer and audience validation.

## Consequences
- Positive: one command makes a service secure, with validation tested end to end and no IdP needed in CI.
- Negative: applying it to an existing service breaks its tokenless endpoint tests until they send tokens
  (by design; done as a pipeline feature).
- Follow-ups: per-account authorization in use cases; IdP choice and `AUTH_*` values per environment;
  problem+json bodies for 401/403.
