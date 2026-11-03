# claude-factory

Personal software factory: a Claude Code plugin marketplace whose plugins implement an
agentic coding pipeline, plus the templates that new projects are created from.

## Layout

```
claude-factory/
├── .claude-plugin/marketplace.json      marketplace "claude-factory"
├── plugins/java-pipeline/
│   ├── .claude-plugin/plugin.json       plugin manifest (version lives here)
│   ├── agents/                          architect-reviewer, test-writer, code-reviewer
│   ├── skills/                          new-feature, write-adr, new-project (+ scripts/)
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
