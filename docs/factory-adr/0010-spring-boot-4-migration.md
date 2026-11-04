# 0010. Spring Boot 4.1 for the factory (factory-parent 2.0.0)

- Status: Accepted
- Date: 2026-11-04
- Deciders: Noel Abi Abdallah

## Context
Spring Boot 3.5 and Spring Framework 6.2 have no more OSS releases. The first image scan (ADR 0009) found two
spring-webmvc CVEs (CVE-2026-47884, CVE-2026-47890) that are fixed only in Spring Framework 7. The owner
accepted them in `.trivyignore.yaml` until 2026-12-03, on the condition that the factory moves to Spring Boot 4 first.
Factory-parent 1.3.0 also overrode Tomcat and Jackson versions to close other findings.

## Decision
- `factory-parent` 2.0.0 inherits `spring-boot-starter-parent` 4.1.2 (Spring Framework 7.0, Tomcat 11, Jackson 3).
  It is a major version because services must change code to adopt it. Java stays at 21.
- The Tomcat and Jackson overrides are removed: Boot 4.1 manages fixed versions. The two Spring MVC exceptions
  are removed; the scan runs with no exceptions.
- Templates use Boot 4's modular starters: `spring-boot-starter-webmvc` and `spring-boot-starter-webmvc-test`.
  The test starter brings `spring-boot-starter-test` with it. Validation and Actuator keep their names.
- `add-postgres` adds `spring-boot-starter-flyway` and `spring-boot-starter-jdbc-test`. Boot 4 auto-configures
  Flyway only through its starter: with the bare Flyway artifact alone, migrations would silently not run.
  `PostgresSetupTest` catches that (checked by removing the starter: the build fails).
- `add-resource-server` adds `spring-boot-starter-security-oauth2-resource-server` and its `-test` starter
  (the old starter name is deprecated in Boot 4).
- Both skills refuse projects on `factory-parent` < 2.0.0 instead of half-migrating them.
- The Dependabot rule that ignored Spring Boot majors is removed.
- No classic starters (`spring-boot-starter-classic`, `-test-classic`): they are a migration aid Boot itself
  recommends leaving, and the templates didn't need them.

## Alternatives considered
- **Stay on 3.5 with commercial support:** pays for fixes the OSS line already has in 4.x; still a migration later.
- **Classic starters as a first step:** smaller diff, but every service would need a second migration.
- **Boot 4.0.x:** 4.1 is current and 4.0 removals were deprecated in 3.5, so skipping straight to 4.1 costs nothing.

## Consequences
- Upgrading a service from `factory-parent` 1.x is a code change, not a version bump. Dependabot's major PR in
  each service will fail until these changes are made in that PR:
  1. `spring-boot-starter-web` → `spring-boot-starter-webmvc`. Replace `spring-boot-starter-test` with
     `spring-boot-starter-webmvc-test` (plus `-jdbc-test`, `-flyway`, `-security-oauth2-resource-server[-test]`
     if the service used add-postgres / add-resource-server).
  2. Moved test packages:
     - `org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc` →
       `org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc`
     - `org.springframework.boot.test.autoconfigure.jdbc.{JdbcTest,AutoConfigureTestDatabase}` →
       `org.springframework.boot.jdbc.test.autoconfigure.*`
     - `org.springframework.boot.actuate.health.HealthEndpointGroups` →
       `org.springframework.boot.health.actuate.endpoint.HealthEndpointGroups`
     - `org.springframework.boot.autoconfigure.security.oauth2.resource.*` →
       `org.springframework.boot.security.oauth2.server.resource.autoconfigure.*`
       (use the non-servlet `JwkSetUriJwtDecoderBuilderCustomizer`; the servlet one is deprecated for removal)
  3. `HttpStatus.UNPROCESSABLE_ENTITY` → `UNPROCESSABLE_CONTENT` (same 422, RFC 9110 name).
  4. Jackson 3: `com.fasterxml.jackson.databind` → `tools.jackson.databind`. Annotations keep
     `com.fasterxml.jackson.annotation`. A custom mapper must be a `JsonMapper` bean.
  5. `@SpringBootTest` no longer provides MockMvc or TestRestTemplate: add `@AutoConfigureMockMvc` or
     `@AutoConfigureTestRestTemplate`.
  6. Run `./mvnw spotless:apply verify` and the image scan.
- payments-service stays on 1.x until the owner asks for its upgrade (it is a factory fixture).
- Sources: Spring Boot 4.0 Migration Guide and 4.1 Release Notes (spring-projects/spring-boot wiki).
