# 0001. Ship the agentic pipeline as a Claude Code plugin

- Status: Accepted
- Date: 2026-11-02
- Deciders: Noel Abi Abdallah

## Context
The agentic-java-starter carried its pipeline (3 agents, 2 skills, 2 hooks) inside each
project's `.claude/` directory. Every new project would get a copy, and improvements to an
agent or hook would have to be repeated by hand in every repo, so the copies would drift.
The pipeline is the reusable part; the project code, architecture rules and specs are not.
Claude Code supports plugins distributed through a marketplace (a git repo with
`.claude-plugin/marketplace.json`), with versioning and updates.

## Decision
Package the pipeline as the `java-pipeline` plugin in a `claude-factory` marketplace repo.
Projects contain only code, docs, `CLAUDE.md`, `ArchitectureTest` and a `.claude/settings.json`
with permissions plus `enabledPlugins`/`extraKnownMarketplaces`. New projects are created from
a template bundled inside the plugin by the `new-project` skill.

## Alternatives considered
- **Copy `.claude/` into each project** — simplest, but changes don't propagate and copies drift.
- **User-level `~/.claude/agents` and `skills`** — shared, but unversioned, not reviewable per
  change, and applies to every repo including non-Java ones.
- **Git submodule for `.claude/`** — versioned, but awkward with hooks paths and per-project overrides.

## Consequences
- Positive: one place to change the pipeline; versioned releases; projects stay small.
- Positive: hooks reference `${CLAUDE_PLUGIN_ROOT}`, so they work wherever the plugin is installed.
- Negative: skills and agents are namespaced (`/java-pipeline:new-feature`,
  `java-pipeline:architect-reviewer`).
- Negative: plugin hooks fire in every project where the plugin is enabled, so the hook
  scripts must no-op outside Maven projects (they check for `pom.xml`).
- Negative: the template lives inside the plugin directory (not at the marketplace root),
  because only the plugin directory is copied into the plugin cache on install.
- Follow-ups: bump `version` in `plugin.json` on every release; add CI that runs
  `claude plugin validate --strict` and a `new-project` smoke test.
