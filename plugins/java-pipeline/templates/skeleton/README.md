# app-skeleton

A Spring Boot 3.5 / Java 21 hexagonal service, created by `/java-pipeline:new-project`.
It starts empty: layer packages, an `ErrorHandler`, architecture rules and CI, no business code.
The agentic pipeline — **spec → plan → architect review → failing tests → implementation →
`./mvnw verify` gate → code review** — comes from the `java-pipeline` plugin; this repo holds only
code, docs and project permissions.

## First run

The build inherits `factory-parent` from GitHub Packages, so Maven needs a read token: a
`<server id="github">` in `~/.m2/settings.xml`, and for CI the repo secret `FACTORY_PACKAGES_TOKEN`
(classic PAT with only `read:packages`). See the claude-factory README, "Shared build".

```bash
./mvnw verify      # must be green before you hand anything to an agent
claude             # accept the workspace-trust prompt and the plugin install prompt
```

Check the plugin loaded: `claude plugin details java-pipeline` (skills, agents, hooks), and in a
session `/hooks` (PostToolUse + Stop from the plugin) and `/plugin` (java-pipeline enabled). Then
start your first feature:

```
/java-pipeline:new-feature <what you want to build>. Write the spec first.
```

Requires `jq` on your PATH (the plugin hooks parse their JSON input with it).

## Runtime

- Health for Kubernetes: `/actuator/health/liveness` and `/actuator/health/readiness`; no other Actuator
  endpoint is exposed and health shows no details.
- Logs are ECS JSON by default; run locally with plain text:
  `./mvnw spring-boot:run -Dspring-boot.run.profiles=local`.
- Graceful shutdown: in-flight requests get up to 20s when the pod stops.

## Image and deployment

- CI pushes `ghcr.io/nabiabdallah/<service>:<sha>` and `:main` on every push to `main` (Jib, distroless,
  non-root; no Docker needed). PRs only run `verify`.
- `deploy/k8s/` is a Kustomize base (Deployment + Service, probes, hardened security context). Create the
  database Secret once, then deploy:
  ```bash
  kubectl create secret generic <service>-db --from-literal=DB_URL=... --from-literal=DB_USERNAME=... --from-literal=DB_PASSWORD=...
  kubectl apply -k deploy/k8s
  ```
  Set the image tag in `deploy/k8s/kustomization.yaml` (`newTag`).
- Build the image locally without pushing (needs network to gcr.io): `./mvnw -DskipTests package jib:buildTar`.

## Supply chain

CI scans the image on every run (Trivy; accepted findings in `.trivyignore.yaml` with a reason and expiry) and,
on `main`, signs the pushed digest and attests the SBOM (Spring Boot's `META-INF/sbom/application.cdx.json`). Verify an image:

```bash
cosign verify ghcr.io/nabiabdallah/<service>@sha256:<digest> \
  --certificate-identity-regexp '^https://github.com/nabiabdallah/<service>/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## What's here

| Path | Role |
|---|---|
| `CLAUDE.md` | Always-loaded context: commands, architecture, rules. Keep it short. |
| `.claude/settings.json` | Permissions (allow Maven/git, ask before push, deny `.env` and edits to `ArchitectureTest`) and enablement of `java-pipeline@claude-factory`. |
| `src/main/java/.../adapter/in/web/ErrorHandler.java` | RFC 9457 problem responses; 404/422 for domain errors, generic 500 with an `errorId`. |
| `src/test/.../ArchitectureTest.java` | The architecture as build-breaking rules. |
| `src/test/.../ApplicationContextTest.java` | Boots the full Spring context. |
| `docs/specs/` | Specs with numbered acceptance criteria — the agents' source of truth. |
| `docs/adr/` | Architecture decisions. |
| `.github/workflows/ci.yml` | CI: JDK 21, `./mvnw verify`. |

## Evolving it
- Add a rule to `ArchitectureTest` every time a review catches the same structural mistake twice.
- Pipeline changes (agents, skills, hooks) belong in the `claude-factory` repo, not here.
