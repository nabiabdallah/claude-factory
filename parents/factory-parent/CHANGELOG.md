# Changelog: factory-parent

All notable changes to the shared Maven build, newest first ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
[semver](https://semver.org/)). Each version is tagged `factory-parent-vX.Y.Z`; the tag publishes it to GitHub
Packages. Services get it through a Dependabot PR. Decisions are in `docs/factory-adr/`.

## [2.1.1] - 2026-11-13

- Base image digest updated (PR #11): the distroless image with zlib1g `+deb13u1`, which fixes CVE-2026-76844 and
  CVE-2026-85091 (HIGH). 2.1.0's digest fails the services' image scan. The change sat on `main` under 2.1.0 without
  a release, so factory CI (which builds against the repo's parent) passed while new services failed.

## [2.1.0] - 2026-11-05

- Maven Enforcer at `validate`: Java 21+, Maven 3.9+, pinned plugins, no SNAPSHOT dependencies or parent, no
  duplicate dependencies, banned dependencies (JUnit 4/vintage, log4j 1, log4j-core before 2.17.1, `javax.*` EE
  APIs, commons-collections before 3.2.2), no runtime dependency compiled for Java 22+ (ADR 0013).
- JaCoCo 0.8.15 coverage floor at `verify`: 80% lines, 70% branches; `factory.coverage.*.minimum` may be raised,
  not lowered.
- `maven-site-plugin` 3.22.0 pinned.

**Upgrading:** a service below the floor or with a banned dependency fails its upgrade PR: add tests or drop the
dependency.

## [2.0.0] - 2026-11-04

- Spring Boot 4.1.2 (Spring Framework 7, Tomcat 11, Jackson 3); the Tomcat/Jackson overrides of 1.3.0 removed
  (ADR 0010).

**Upgrading:** breaking. Follow the service checklist in ADR 0010.

## [1.3.0] - 2026-11-03

- Distroless base image pinned to a digest (`java21-debian13:nonroot`); a weekly factory workflow proposes new
  digests (ADR 0009).
- Spring Boot's CycloneDX plugin switched on: SBOM at `META-INF/sbom/application.cdx.json`.
- Tomcat 10.1.59 and Jackson 2.21.8 overrides for fixable CVEs in Boot 3.5.16.

## [1.2.0] - 2026-11-03

- Jib 3.5.2: distroless non-root image, OCI, port 8080, `MaxRAMPercentage=75`, `ExitOnOutOfMemoryError`,
  reproducible (ADR 0007).

## [1.1.0] - 2026-11-03

- embedded-postgres 2.2.2 and Postgres binaries 18.6.0 managed, for add-postgres (ADR 0004).

## [1.0.0] - 2026-11-03

- First version: Spring Boot 3.5.16 parent, Java 21, ArchUnit and Spotless versions, Spotless check at `verify`,
  Mockito as a Java agent in Surefire (ADR 0003).
