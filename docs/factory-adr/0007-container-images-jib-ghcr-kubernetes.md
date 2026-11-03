# 0007. Container images with Jib on distroless, pushed to GHCR; Kustomize base for Kubernetes

- Status: Accepted
- Date: 2026-11-03
- Deciders: Noel Abi Abdallah

## Context
Services will run on Kubernetes (owner decision). There is no Docker daemon in WSL or the Claude Code
sandbox, so images must be built without one. Images should be small, non-root and reproducible, and
manifests must use the health probes from ADR 0006.

## Decision
- **Build:** Jib (`jib-maven-plugin` 3.5.2), configured once in `factory-parent` (1.2.0): base
  `gcr.io/distroless/java21-debian12:nonroot` (no shell, uid 65532), OCI format, port 8080, JVM flags
  `-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError`, `org.opencontainers.image.source` label;
  reproducible (fixed creation time).
- **Publish:** each service's CI has an `image` job that runs only on pushes to `main` after `verify`,
  `./mvnw jib:build` to `ghcr.io/nabiabdallah/<service>` with tags `<sha>` and `main`, authenticated with
  the repo's own `GITHUB_TOKEN` (`packages: write`). PRs never push images.
- **Deploy manifests:** a Kustomize base in `deploy/k8s/` (Deployment + ClusterIP Service): 2 replicas,
  `maxUnavailable: 0`; startup, liveness and readiness probes on Actuator; requests 250m/512Mi, memory limit
  768Mi, no CPU limit; non-root, read-only root filesystem with an `emptyDir` `/tmp`, no privilege
  escalation, all capabilities dropped, `RuntimeDefault` seccomp, no service-account token;
  `terminationGracePeriodSeconds: 30` (> the 20s graceful shutdown); database settings from an optional
  Secret `<service>-db`, never in git. The image tag is set in `kustomization.yaml`.
- **Validation:** factory CI renders every template's manifests with `kubectl kustomize` and checks them
  with `kubeconform -strict` (Kubernetes 1.31 schemas), and builds the skeleton image with `jib:buildTar`.

## Alternatives considered
- **Buildpacks (`spring-boot:build-image`)** — Spring's default, but needs a Docker daemon and gives less
  control over the base image.
- **Dockerfile** — explicit, but one more file per service and a Docker daemon to build.
- **`eclipse-temurin` JRE base** — has a shell for debugging, but a larger attack surface.
- **Helm** — more flexible templating than needed for one service; Kustomize is built into kubectl.

## Consequences
- Positive: every service gets a small, non-root, reproducible image and hardened manifests for free.
- Negative: no shell in the container; debug with `kubectl debug` ephemeral containers.
- Negative: the distroless `nonroot` tag moves; it is not pinned by digest, and Dependabot doesn't update
  Jib's base image. Pinning a digest is a follow-up once a release cadence exists.
- Follow-ups: ingress/gateway, network policies, a deploy job and environments (overlays) once a cluster
  exists; image signing and SBOM.
