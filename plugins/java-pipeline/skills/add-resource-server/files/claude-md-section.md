
## Security (OAuth2 resource server)
- Every request needs a valid JWT except `/actuator/health/**`. Checked: signature (issuer's keys), issuer
  (`AUTH_ISSUER_URI`), audience (`AUTH_AUDIENCE`, default the service name), expiry. No issuer → no start.
- Scopes: `__SVC__:read` for GET, `__SVC__:write` for everything else (`config/SecurityConfig`). Refine per
  endpoint there; never make an endpoint public without a spec saying so.
- Per-account rules ("only your own account") are business rules: pass the caller's subject (`jwt.getSubject()`)
  from the controller into the command and enforce it in the use case, with tests.
- Tests: endpoint tests in a Spring context send `TestTokens.withScopes("__SVC__:read")` as the Authorization
  header (real signed tokens from a local stand-in issuer, `support/TestJwtInitializer`). Cover 401 and 403 for new endpoints.
- Never log tokens, Authorization headers or full claims.
