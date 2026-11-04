# 0009. Supply chain: pins, SBOM, keyless signing and image scanning

- Status: Accepted
- Date: 2026-11-03
- Deciders: Noel Abi Abdallah

## Context
Services built by the factory ship as container images. Before this change, the same build could pull a
different base image (tag `nonroot` moves), Actions were referenced by movable tags, nothing recorded what an
image contains, nothing proved an image came from our CI, and nothing failed a build on known vulnerabilities.
The repos are private on a free GitHub plan: code scanning (SARIF, CodeQL, dependency review) isn't available.

## Decision
- **Base image pinned to a digest** in `factory-parent` (`factory.image.base` = `…:nonroot@sha256:…`). A weekly
  factory workflow (`base-image.yml`) reads the current digest from the registry and opens a PR when it changes;
  it's released like any parent change.
- **Actions pinned to commit SHAs** (`@<sha> # vX.Y.Z`) in factory and template workflows; Dependabot updates
  the pins. **Downloaded CI tools** (cosign, Trivy) are pinned by version and sha256 in
  `.github/scripts/ci-tools.sh`, bumped by hand.
- **SBOM**: Spring Boot 3.5 manages `cyclonedx-maven-plugin` (version and execution) but runs it only when a
  project lists it; `factory-parent` lists it, without a version or configuration of its own. It writes the
  runtime dependencies to `META-INF/sbom/application.cdx.json` (in the jar, so also in the image). CI keeps it as
  an artifact and attests it. No new version to maintain: it moves with Boot.
- **Image scan**: template CI builds the image tarball on every run and Trivy scans it; HIGH/CRITICAL findings
  with a fix fail the build. Exceptions go in `.trivyignore.yaml` with a reason and an expiry date.
- **Keyless signing**: on pushes to `main`, CI signs the pushed digest with cosign (Sigstore, GitHub OIDC; no
  keys to manage) and attaches the SBOM as a signed CycloneDX attestation.
- **Enforced by factory CI**: `ci/check-supply-chain.sh` fails on an unpinned Action, an undigested base image,
  an unpinned tool, a template CI without scan/sign/attest, or a missing SBOM; factory CI also scans the
  skeleton image.

## Alternatives considered
- **Docker Hub / ghcr scanning or GitHub code scanning** — needs a paid plan on private repos.
- **Trivy/cosign GitHub Actions** instead of binaries — more moving parts to pin, and third-party Actions have
  been compromised by tag moves; a checksum-verified binary is simpler to audit.
- **Key-based signing** — keys to store and rotate; keyless ties the signature to the workflow identity.
- **Floating base tag** — always current, but builds aren't reproducible and a bad push reaches every service.

## Consequences
- Positive: reproducible base, auditable contents, provenance of every pushed image, known-vulnerable images
  don't merge.
- Negative: a new upstream CVE can turn CI red without a code change (intended); fix by updating or by a
  dated exception.
- Negative: the base-image PR is opened with `GITHUB_TOKEN`, which doesn't start CI — close and reopen it.
  The repo setting "Allow GitHub Actions to create pull requests" must be on.
- Negative: signatures aren't enforced at deploy time yet (admission policy) — deploy safety (#3).
- Existing services get pins/SBOM through the parent bump, but not the CI changes (templates are copied once).

## First scan (2026-11-03)
The first CI scan failed with 32 fixable HIGH/CRITICAL findings:
- **Base image:** the `java21-debian12` line lagged Debian's security updates, so the base moved to
  `java21-debian13`, still Java 21.
- **Tomcat and Jackson:** both were pinned to fixed versions in `factory-parent`.
- **Spring MVC:** CVE-2026-47884 and CVE-2026-47890 in `spring-webmvc` 6.2.19 are fixed only in Spring 7.
  Boot 3.5 and Spring 6.2 are out of OSS support, so the owner accepted a 30-day exception in `.trivyignore.yaml`
  (expires 2026-12-03). The factory migrates to Spring Boot 4 before that date.
