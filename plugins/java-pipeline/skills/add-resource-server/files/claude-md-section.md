
## Security (OAuth2 resource server)
- Every request needs a valid JWT except `/actuator/health/**`. Checked: signature (issuer's keys), issuer
  (`AUTH_ISSUER_URI`), audience (`AUTH_AUDIENCE`, default the service name), expiry, and a usable `sub` (present,
  not blank, ≤ 255 chars, no control characters). No issuer, a blank issuer, an issuer not on https (plain http
  only to localhost / 127.x / [::1]) or a blank audience → no start. Calls to the issuer are https-only too. Calls to the issuer time out after 3s (request refused with 401).
- Scopes: `__SVC__:read` for GET and HEAD, `__SVC__:write` for everything else (`config/SecurityConfig`). Refine per
  endpoint there; never make an endpoint public without a spec saying so.
- Per-account rules ("only your own account") are business rules: pass the caller's subject (`jwt.getSubject()`)
  from the controller into the command and enforce it in the use case, before any other rule (someone else's
  data answers like not-found). Test each operation with a second caller.
- Idempotency keys are unique per (caller subject, key): the same key from another caller is a separate
  request, never a replay of the first caller's response. Test two callers with the same key.
- Tests: endpoint tests in a Spring context send `TestTokens.withScopes("__SVC__:read")` as the Authorization
  header (real signed tokens from a local stand-in issuer, `support/TestJwtInitializer`). Cover 401 and 403 for new endpoints.
- Never log tokens, Authorization headers or full claims.
- Kubernetes: pass `AUTH_*` (and any Secret value) as explicit `env` keys, never `envFrom`: a stray key such as
  `SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_AUDIENCES=` would silently weaken token checks.
