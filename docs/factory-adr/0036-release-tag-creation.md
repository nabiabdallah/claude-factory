# 0036. Only the factory App and admins create release tags

- Status: Accepted
- Date: 2026-11-17
- Deciders: Noel Abi Abdallah
- Amends: [ADR 0016](0016-public-repos-and-guardrails.md) (the `release tags` ruleset)

## Context
ADR 0016's `release tags` ruleset stops anyone from moving or deleting a `java-pipeline-v*` or `factory-parent-v*`
tag, but anyone with write access may create one. A created tag is a release: `release-plugin.yml` and
`publish-parent.yml` run on it, and projects pin it (ADR 0015). Since ADR 0026, `release-tag.yml` creates these
tags with the factory App's token when a version bump merges, so nobody else needs to. The roadmap listed this as
open under B0; the owner said yes on 2026-11-17.

## Decision
- `ci/protect-repo.sh` adds a second tag ruleset to the factory repo, `release tag creation`: the same tag
  patterns, one rule (`creation`), and two bypass actors, both `always`: the factory App (`Integration`, its
  numeric id) and the `Repository admin` role (a tag pushed by hand, as in the comments of `release-plugin.yml`
  and `publish-parent.yml`).
- It is a separate ruleset because a bypass covers every rule in its ruleset. In one ruleset with `update` and
  `deletion`, the App could also move or delete a release tag. `release tags` keeps no bypass.
- Both rulesets read the tag patterns from one list, so they can't drift apart. A test checks they match.
- The App's id comes from `FACTORY_APP_ID`, or the script looks it up from the repo's `FACTORY_APP_SLUG` variable
  (ADR 0021) with the admin's `gh` login. If it finds no numeric id it stops before writing anything.
- `ci/test-protect-repo.sh` covers the ruleset, the lookup and the refusal.

## Alternatives considered
- **Add `creation` and the bypass to `release tags`.** Rejected: the bypass would also let the App move or delete
  a release.
- **Only the App, no admin bypass.** Rejected: a release could not be tagged by hand when `release-tag.yml` is
  broken, and fixing it needs a release.
- **Hard-code the App's id.** Rejected: the App's API endpoint isn't public, so the id isn't known without a
  login, and a recreated App (ADR 0021) would get a new one.

## Consequences
- Positive: a collaborator or a leaked write token can't publish a plugin or parent release.
- Negative: the owner must re-run `ci/protect-repo.sh nabiabdallah/claude-factory factory` after merging; a
  session may not change rulesets.
- When web-pipeline gets release tags (frontend step F2), its pattern goes into the one list.
