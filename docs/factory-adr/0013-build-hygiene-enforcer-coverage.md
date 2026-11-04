# 0013. Build hygiene: Maven Enforcer rules and a raise-only coverage floor in factory-parent

- Status: Accepted
- Date: 2026-11-05
- Deciders: Noel Abi Abdallah

## Context
factory-parent checked formatting (Spotless) and the templates checked architecture (ArchUnit), but nothing
stopped a build on the wrong JDK or Maven, a plugin or dependency without a fixed version, a SNAPSHOT, a
dependency the factory has left behind (JUnit 4, `javax.*` after the Jakarta move, log4j 1), a library compiled
for a newer Java than the Java 21 runtime image (it fails only at runtime with `UnsupportedClassVersionError`),
or code merged without tests. Agents write most of the code, so these have to be build failures, not review notes.

## Decision
All in factory-parent 2.1.0, so every service gets the rules with a version bump.
- **Maven Enforcer** (`maven-enforcer-plugin` 3.6.3, managed by Spring Boot; execution `factory-rules` at
  `validate`):
  - `requireJavaVersion [21,)`, `requireMavenVersion [3.9,)`;
  - `requirePluginVersions` (no unpinned, `LATEST`, `RELEASE` or SNAPSHOT plugins). `maven-site-plugin` 3.22.0
    is pinned in the parent's pluginManagement, because Maven's default lifecycle binds it and Spring Boot
    doesn't manage it;
  - `requireReleaseDeps` (no SNAPSHOT dependencies or parent, also on SNAPSHOT builds) and
    `banDuplicatePomDependencyVersions`;
  - `bannedDependencies`, transitive too: `junit:junit`, `org.junit.vintage`, `log4j:log4j`,
    `log4j-core` before 2.17.1, `javax.servlet`, `javax.persistence`, `javax.validation`,
    `javax.annotation:javax.annotation-api`, `javax.xml.bind`, `javax.ws.rs`, `commons-collections` before 3.2.2.
    A service that really needs one excludes it from the rule in its own POM, with a comment, so it shows in
    review;
  - `enforceBytecodeVersion maxJdkVersion=21` for compile and runtime scope, from
    `org.codehaus.mojo:extra-enforcer-rules` 1.12.1 (a build-only dependency; the only rule that checks a
    library's class-file version). It passes on both templates, including multi-release jars.
- **Coverage floor:** `jacoco-maven-plugin` 0.8.15 (June 2026; 0.8.16 was 10 days old, so Dependabot proposes
  it later). `prepare-agent` fills `@{argLine}`, which the parent already passes to Surefire with the Mockito
  agent. `report` and `check` run at `verify`: bundle LINE covered ratio ≥ 0.80 and BRANCH ≥ 0.70, excluding
  `**/*Application.class` (only `main`). Templates' CI uploads `target/site/jacoco` as the `coverage` artifact.
- **Raise-only:** the minimums are the properties `factory.coverage.line.minimum` and
  `factory.coverage.branch.minimum`. Enforcer `requireProperty` rules with regexes accept only values ≥ 0.80 and
  ≥ 0.70, so a service can raise them in its POM, and a lower value fails at `validate`.
- **Agents:** the template `CLAUDE.md` forbids lowering the floor, adding JaCoCo excludes, skipping Enforcer or
  JaCoCo, or excluding a banned dependency to get green; the code-reviewer marks any of these MUST FIX unless the
  owner accepted a stated reason.
- **Versions:** factory-parent 2.1.0 (minor: no API or configuration change for services, but a service below
  the floor or with a banned dependency fails its upgrade PR, which is the intended signal); java-pipeline
  0.14.0. `add-postgres` still needs only 2.0.0.
- **Tests:** the skeleton was below the branch floor (ErrorHandler: an explicit `instance` is kept, a non-problem
  body passes through), so it gained two tests. `ci/test-build-hygiene.sh` runs in factory CI on a generated
  project with Postgres and the resource server, and expects each of these to fail the build: JUnit 4, a SNAPSHOT
  dependency, a dependency built for Java 22, a plugin without a version, lowered line and branch floors, and
  untested code.

## Alternatives considered
- **`dependencyConvergence` / `requireUpperBoundDeps`** — with Spring Boot's BOM they fail on many harmless
  transitive differences; Boot's dependency management already decides the versions.
- **Per-package or per-class thresholds** — stricter, but noisy on small services; the bundle floor plus review
  is enough to start.
- **Mutation testing (PIT) as a gate** — a better measure of test quality than line coverage, but slow; the
  new-feature skill already asks for targeted mutation checks.
- **factory-parent 3.0.0** — the rules can break a service's build, but nothing in the service has to change
  except tests or a dependency; owner chose a minor version.

## Consequences
- Positive: toolchain, version and dependency mistakes fail in seconds at `validate`; coverage can only go up.
- Negative: line/branch coverage says nothing about assertion quality; reviewers and mutation checks still matter.
- Negative: a name-based exclude (`*Application`) also skips any other class whose name ends in "Application".
- Negative: projects can still override the parent's plugin configuration; only review catches that.
- Follow-ups: PIT as a CI gate once services are bigger; license rules.
