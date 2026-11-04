# claude-factory

Personal software factory: a Claude Code plugin marketplace whose plugins implement an
agentic coding pipeline, plus the templates that new projects are created from.

Status and next steps: [docs/ROADMAP.md](docs/ROADMAP.md).

## Layout

```
claude-factory/
├── .claude-plugin/marketplace.json      marketplace "claude-factory"
├── plugins/java-pipeline/
│   ├── .claude-plugin/plugin.json       plugin manifest (version lives here)
│   ├── agents/                          architect-reviewer, test-writer, code-reviewer
│   ├── skills/                          new-feature, write-adr, new-project, add-postgres, add-resource-server
│   ├── hooks/                           hooks.json, format-java.sh, verify-gate.sh
│   ├── bin/mvnw-sandboxed               ./mvnw + sandbox proxy (on PATH while enabled)
│   └── templates/                       what /java-pipeline:new-project copies
│       ├── skeleton/                    default: empty hexagonal service
│       └── payments-example/            the original payments starter, as a worked example
├── parents/factory-parent/             shared Maven build every service inherits (GitHub Packages)
├── docs/factory-adr/                    decisions about the factory itself
└── README.md
```

Templates sit inside the plugin because only the plugin directory is copied into the
plugin cache on install (see `docs/factory-adr/0001-pipeline-as-plugin.md`).

## Install

From a shell (or the same commands prefixed with `/plugin` inside a session):

```bash
claude plugin validate ~/dev/factory/claude-factory          # optional sanity check
claude plugin marketplace add ~/dev/factory/claude-factory   # local directory marketplace
claude plugin install java-pipeline@claude-factory
claude plugin list                                           # java-pipeline@claude-factory ✔ enabled
```

Once the repo is on GitHub, add it by `owner/repo` instead:
`claude plugin marketplace add <owner>/claude-factory`.

Projects created by `new-project` also declare the marketplace and enable the plugin in their
own `.claude/settings.json`, so opening the project prompts to install it if it's missing.

## Use

```
/java-pipeline:new-project customer-service com.example.customers                 # skeleton
/java-pipeline:new-project ledger-demo com.example.ledger --template payments-example
cd ~/dev/projects/customer-service && claude
/java-pipeline:add-postgres                     # optional: Postgres, Flyway, embedded-Postgres tests
/java-pipeline:add-resource-server              # optional: OAuth2/JWT auth (AUTH_ISSUER_URI), test tokens
/java-pipeline:new-feature Add GET /customers/{id}. Write the spec first.
```

Agents are available as `java-pipeline:architect-reviewer`, `java-pipeline:test-writer` and
`java-pipeline:code-reviewer`. Hooks: PostToolUse formats edited Java files with Spotless;
Stop runs `./mvnw verify` when Java/POM files changed and blocks finishing while it's red
(gives up after 3 attempts). Both hooks do nothing outside Maven projects.

## Shared build: factory-parent

Services inherit `io.github.nabiabdallah.factory:factory-parent`, published to GitHub Packages in
this repo (see `docs/factory-adr/0003-shared-parent-pom-on-github-packages.md`).

**One-time setup on a machine:**
1. Create a classic personal access token with only `read:packages`.
2. Put it in `~/.m2/settings.xml` (`chmod 600`):
   ```xml
   <settings><servers><server>
     <id>github</id><username>nabiabdallah</username><password>TOKEN</password>
   </server></servers></settings>
   ```
3. Allow `maven.pkg.github.com` and `github-registry-files.githubusercontent.com` (where GitHub serves the
   package files) in the sandbox: `sandbox.network.allowedDomains` in `~/.claude/settings.json`.

**Per service repo on GitHub:** add the same token as the secret `FACTORY_PACKAGES_TOKEN`
(`gh secret set FACTORY_PACKAGES_TOKEN --repo <owner>/<service>`); the service's CI reads it.

**Release a new parent:** bump `<version>` in `parents/factory-parent/pom.xml`, update the templates'
`<parent><version>`, commit, push, then `git tag factory-parent-vX.Y.Z && git push origin factory-parent-vX.Y.Z`.
`publish-parent.yml` checks the tag matches the pom and deploys. Services pick it up by bumping their
parent version.

## Images and Kubernetes

Services build their image with Jib (configured in `factory-parent` 1.2.0+: distroless, non-root) and CI
pushes `ghcr.io/nabiabdallah/<service>:<sha>` and `:main` on pushes to `main`. Each service has a Kustomize
base in `deploy/k8s/`. Factory CI validates the templates' manifests with kubeconform and builds the
skeleton image with `jib:buildTar` (ADR 0007).

## Supply chain

`factory-parent` 1.3.0+ pins the base image to a digest; Spring Boot writes the SBOM
(`META-INF/sbom/application.cdx.json`). Template CI scans
every image with Trivy (fails on fixable HIGH/CRITICAL) and, on `main`, signs the pushed digest with cosign
(keyless) and attests the SBOM. Actions are pinned to commit SHAs. `ci/check-supply-chain.sh` enforces all of it
in factory CI; `base-image.yml` opens a weekly PR when distroless publishes a new digest (ADR 0009). Turn on
**Settings → Actions → General → Allow GitHub Actions to create and approve pull requests** for that PR.

## Dependency updates (Dependabot)

Every repo has `.github/dependabot.yml` (the templates carry it to new services): weekly PRs, minor/patch
grouped, majors separate, all through normal CI (ADR 0005). Each repo needs the **Dependabot** secret
`FACTORY_PACKAGES_TOKEN` (same `read:packages` token; separate from the Actions secret):

```bash
gh secret set FACTORY_PACKAGES_TOKEN --app dependabot --repo nabiabdallah/<repo>
```

Spring Boot or plugin bump: Dependabot PR on `factory-parent` → merge → tag a new parent → Dependabot
opens a parent-version PR in every service.

`factory-parent` 2.0.0 is Spring Boot 4.1. Moving a service from 1.x is a code change. The checklist is in
`docs/factory-adr/0010-spring-boot-4-migration.md`.

`factory-parent` 2.1.0 adds build rules (`docs/factory-adr/0013-build-hygiene-enforcer-coverage.md`): Maven
Enforcer at `validate` (Java 21+, Maven 3.9+, pinned plugins, no SNAPSHOT or banned dependencies, no dependency
compiled for Java 22+) and a JaCoCo coverage floor at `verify` (80% lines, 70% branches; a service may raise it,
not lower it). A service that misses either fails on the upgrade PR: add tests or drop the dependency.

## Update

- **Local directory marketplace**: Claude Code reads the plugin in place. Edits take effect at
  the next session start or after `/reload-plugins`; no version bump needed.
- **GitHub marketplace**: bump `version` in `plugins/java-pipeline/.claude-plugin/plugin.json`
  for every release, commit, tag (`java-pipeline-vX.Y.Z`) and push. Users pick it up with
  `claude plugin marketplace update claude-factory` (then `/reload-plugins` or a new session).
  Without a version bump, installed copies stay on the old version.

## Develop

```bash
claude plugin validate ~/dev/factory/claude-factory             # marketplace + plugin
claude plugin validate ~/dev/factory/claude-factory/plugins/java-pipeline
claude --plugin-dir ~/dev/factory/claude-factory/plugins/java-pipeline   # try without installing
```

Record factory-level decisions in `docs/factory-adr/`.
