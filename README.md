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
│   └── templates/spring-service/        what /java-pipeline:new-project copies
├── docs/factory-adr/                    decisions about the factory itself
└── README.md
```

The template sits inside the plugin because only the plugin directory is copied into the
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
/java-pipeline:new-project payments-service com.example.payments
cd ~/dev/projects/payments-service && claude
/java-pipeline:new-feature Add GET /accounts/{id}/balance. Write the spec first.
```

Agents are available as `java-pipeline:architect-reviewer`, `java-pipeline:test-writer` and
`java-pipeline:code-reviewer`. Hooks: PostToolUse formats edited Java files with Spotless;
Stop runs `./mvnw verify` when Java/POM files changed and blocks finishing while it's red
(gives up after 3 attempts). Both hooks do nothing outside Maven projects.

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
