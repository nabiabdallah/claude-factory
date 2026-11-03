---
name: add-resource-server
description: Protect the current java-pipeline service as an OAuth2 resource server — every request needs a valid JWT (signature, issuer, audience, expiry) except health probes; GET needs <service>:read, other methods <service>:write; real signed test tokens (TestTokens), no identity provider needed for tests. Use when the user asks to add authentication, authorization, security, OAuth2 or JWT to a service.
disable-model-invocation: true
---

# Add resource server (OAuth2 / JWT)

1. Confirm you are in the service's root (`pom.xml` inheriting `factory-parent`, with
   `spring-boot-starter-actuator`) and the working tree is clean. If not, stop and tell the user.
2. Create a branch, e.g. `git switch -c security/resource-server`.
3. Run the script exactly once from the project root:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/add-resource-server/scripts/add-resource-server.sh"
   ```

   It adds the dependencies, `config/SecurityConfig`, issuer/audience properties (`AUTH_ISSUER_URI`,
   `AUTH_AUDIENCE`), test support (`TestJwtInitializer`, `TestTokens`, a probe controller), `SecurityTest`,
   a `CLAUDE.md` section and an ADR, then runs `./mvnw verify`. It refuses to overwrite and does not commit.
4. If verify fails because existing endpoint tests now get 401: that is expected. Do not weaken
   `SecurityConfig`. Treat updating those tests (send `TestTokens.withScopes(...)`, add 401/403 cases) as a
   feature: run it through `/java-pipeline:new-feature` with a short spec, or ask the user how to proceed.
5. Show the user `git status` and a summary of the diff; commit only when they agree, staging files by path.
