# Spring service (java-pipeline template)

A Spring Boot 3.5 / Java 21 hexagonal service, created by `/java-pipeline:new-project`.
The agentic pipeline — **spec → plan → architect review → failing tests → implementation →
`./mvnw verify` gate → code review** — comes from the `java-pipeline` plugin; this repo
holds only code, docs and project permissions.

## First run

```bash
./mvnw verify      # must be green before you hand anything to an agent
claude             # accept the workspace-trust prompt and the plugin install prompt
```

Check the plugin loaded: `claude plugin details java-pipeline` (3 skills, 3 agents, 2 hooks;
`/agents` no longer lists agents as of Claude Code 2.1.316), and in a session `/hooks`
(PostToolUse + Stop from the plugin), `/plugin` (java-pipeline enabled). Then:

```
/java-pipeline:new-feature Add a GET /accounts/{id}/balance endpoint. Write the spec first.
```

Requires `jq` on your PATH (the plugin hooks parse their JSON input with it).

## What's here

| Path | Role |
|---|---|
| `CLAUDE.md` | Always-loaded context: commands, architecture, rules. Keep it short. |
| `.claude/settings.json` | Permissions (allow Maven/git, ask before push, deny `.env` and edits to `ArchitectureTest`) and enablement of `java-pipeline@claude-factory`. |
| `src/test/.../ArchitectureTest.java` | The architecture as build-breaking rules. |
| `docs/specs/` | Specs with numbered acceptance criteria — the agents' source of truth. |
| `docs/adr/` | Architecture decisions. |

## Sample domain
Same-currency transfer between accounts (`POST /transfers` with an `Idempotency-Key` header),
with in-memory adapters. See `docs/specs/0001-transfer-between-accounts.md`.

## Evolving it
- Add a rule to `ArchitectureTest` every time a review catches the same structural mistake twice.
- Pipeline changes (agents, skills, hooks) belong in the `claude-factory` repo, not here.
