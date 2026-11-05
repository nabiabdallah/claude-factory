# 0015. Releases: tags, changelogs, pinned plugin in projects, onboarding guide

- Status: Accepted
- Date: 2026-11-05
- Deciders: Noel Abi Abdallah

## Context
Generated projects declared the marketplace as `{"source": "github", "repo": "nabiabdallah/claude-factory"}`, so
every project followed `main`: a plugin change (0.15.0's management port, which add-resource-server now requires)
reached old projects whose tests were never updated for it. factory-parent had tags; the plugin had none, and
neither had a record of changes beyond commit subjects. Setup was spread over READMEs and ROADMAP's working notes.

## Decision
- **Tags:** `java-pipeline-vX.Y.Z` beside `factory-parent-vX.Y.Z`; semver, before 1.0.0 a minor version may need
  action in projects. Tags are never moved or reused. No tags are backfilled for older plugin versions.
- **Pinned projects:** Claude Code's GitHub marketplace source takes `ref` (branch or tag) and `sparsePaths`
  (checked in the 2.1.318 CLI's settings schema). `new-project` writes
  `"ref": "java-pipeline-v<plugin.json version>"` and `"sparsePaths": [".claude-plugin", "plugins"]` into the
  project's `.claude/settings.json`; the template file stays ref-less so the factory's own CI isn't tied to a tag.
  Upgrading a project means bumping `ref` after reading the changelog.
- **Changelogs:** `plugins/java-pipeline/CHANGELOG.md` (backfilled 0.1.0–0.15.0) and
  `parents/factory-parent/CHANGELOG.md` (1.0.0–2.1.0), Keep a Changelog format, with an **Upgrading** note
  wherever a project must act.
- **Checks:** `ci/check-release-notes.sh` runs in factory CI on every PR (each component's newest changelog section
  is its current version, and is not empty) and in both release workflows (`--tag`: the tag names a known
  component and equals its version). `release-plugin.yml` creates the GitHub Release with that section as its body
  (`contents: write` in that job only); `publish-parent.yml` runs the same tag check before deploying.
  `ci/test-release-notes.sh` covers 10 cases (bump without notes, notes without bump, wrong or unknown tag, ...).
  Factory CI also checks the generated `settings.json` pin.
- **Onboarding:** `docs/ONBOARDING.md`, from an empty machine to a deployed change with a check per step; ROADMAP's
  machine notes moved into its troubleshooting section; the README links to it. `ci/check-docs.sh` fails on any
  broken relative link or anchor in the factory's Markdown.
- java-pipeline 0.16.0; `java-pipeline-v0.16.0` is the first plugin tag.

## Alternatives considered
- **Follow `main` (no ref)** — no release overhead, but every merge reaches every project at once, untested
  against its code.
- **Pin a commit SHA** — the schema allows `sha` for plugin sources; a tag reads better in settings and carries a
  changelog section.
- **One combined version for the whole factory** — simpler, but factory-parent reaches services through Maven and
  Dependabot while the plugin reaches them through Claude Code; they move at different speeds.

## Consequences
- Positive: a project keeps the agents, skills and hooks it was built with until someone upgrades it on purpose,
  with notes on what to do.
- Negative: every plugin change needs a version bump, a changelog section and a tag; CI enforces the first two.
- Negative: Dependabot can't bump the plugin `ref`; upgrades are manual.
- Negative: projects created before 0.16.0 still follow `main` until pinned (changelog 0.16.0, Upgrading).
