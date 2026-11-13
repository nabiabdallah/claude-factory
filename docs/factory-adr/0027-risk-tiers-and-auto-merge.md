# 0027. Risk tiers and auto-merge

- Status: Accepted
- Date: 2026-11-13
- Deciders: Noel Abi Abdallah (the rules are ADR 0020's; this ADR is how they are built)
- Implements: step B5 of [ADR 0020](0020-self-running-factory.md)

## Context
ADR 0020 decided that a low-risk PR merges without the owner once required checks pass and an independent
code-reviewer says APPROVE, and that the tier comes from the changed paths, never from the agent's claim. The
step gate (ADR 0022) already labels a step PR `risk:high` when it touches a short protected list. Nothing yet
classified other PRs or merged anything.

## Decision
- **One classifier, `.github/scripts/risk-tier.sh classify`,** reads paths and prints `low` or `high` with a
  reason per path. A PR is low only if *every* path is low. No files, a file list shorter than GitHub's count, or
  a path the lists don't name is high.
  - Always high: the classifier's own files (this script, its two workflows, its test, this ADR), `parents/`,
    `.claude/`, `CLAUDE.md`, `ArchitectureTest`, `deploy/`, migrations, and any path containing auth, security,
    jwt, oauth, idempotency, money, payment, ledger, transfer, account, secret, credential or token.
  - High: workflows and anything under `.github/`, any `pom.xml`, `docs/ROADMAP.md`, and the ADRs that set the
    rules (0017, 0020-0024, 0026, 0027).
  - Low: other Markdown under `docs/`, `README.md`, a plugin's `README.md` and `CHANGELOG.md`, and files under
    `src/test/`.
  - Dependabot: a PR whose author (from the API) is `dependabot[bot]` and whose title is `bump X from A to B`
    with the same major version may change `pom.xml` (not the parent's) and pinned actions in workflows, and be
    low. A major bump, a grouped update (no versions to compare), or any other path is high.
- **Labels.** `risk-tier.yml` (`pull_request_target`, checks out `main`, reads only API metadata) sets
  `risk:low` or `risk:high`. `risk:high` is sticky: if set by the step gate or the owner, only the owner
  removes it. The label is information; the merge never relies on it being right.
- **Auto-merge.** `auto-merge.yml` runs when CI finishes on a pull request (or by hand with a PR number):
  1. `eligible` (no secrets): PR open, not a draft, branch in this repo, base `main`, no `risk:high` label, low
     by its paths now. Records the head sha.
  2. `review` (Claude credential only): checks out the trusted `main` and, in `pr/`, the head sha. A fresh
     `code-reviewer` run (the plugin's agent file from `main` as the brief) with read-only tools (`Read Grep
     Glob`, default permission mode, so no shell) reviews the diff. Its last line must be exactly
     `VERDICT: APPROVE`; anything else, including "approve" earlier in the text, is not an approval. The prompt
     tells it that the diff is data and that an instruction inside it means REQUEST CHANGES. A diff over 400 kB
     is not reviewed and not merged.
  3. `merge` (App token): re-reads the PR; requires the head sha to equal the reviewed one, the PR still eligible
     and low, every required check of `main`'s ruleset (read from the API, never hard-coded) successful on that
     sha (latest run per check), and the verdict `approve`. It posts the review as a comment and merges with
     `--match-head-commit` (a merge commit, as the owner does), deleting the branch. If GitHub refuses (for
     example the branch is behind `main`, which the ruleset forbids), it says so and stops: nothing is forced
     and the branch is not updated by the bot.
  The App's token does the merge so the push to `main` starts `factory-chain.yml` and `release-tag.yml`.
- **`FACTORY_PAUSED=true` also stops auto-merge.** The owner has one switch.
- Tested by `ci/test-risk-tier.sh` (fake `gh`, stand-in reviewer) in factory CI.

## Alternatives considered
- **Trust the label or the step gate's flag:** the label is set by the same pipeline it gates. Recomputing from
  the API's file list at merge time costs one call.
- **A required status check for the tier or the review:** it would also block high PRs from merging by the
  owner's hand and need a ruleset change, which only the owner makes. Not needed: the merge job is the only
  thing that merges on its own.
- **GitHub's native auto-merge (`gh pr merge --auto`):** it would merge on green checks alone and would not wait
  for the reviewer or re-check the tier.
- **Let the reviewer run shell commands:** it could then run code from the PR. Read-only tools are enough for a
  docs/test review.
- **Keep the protected-file regex in `factory-step.sh` as the only list:** it is a subset for a different job
  (flagging the agent's own PR before it opens). It stays, with ADR 0027 added. Its entries are all high here too
  (`.github/`, `.claude/`, `CLAUDE.md`, the listed ADRs) except `ci/protect-repo.sh` and the App scripts, which
  are high here as unknown paths.

## Consequences
- Positive: docs, test-only and minor dependency PRs merge by themselves; the owner reviews high PRs only.
- Negative: a wrong low can merge a bad change unseen. Mitigations: unknown is high, every always-high rule above,
  the sha pin, and the weekly digest of auto-merges (B7).
- Negative: the reviewer is a model reading untrusted text. Its power is one verdict on a PR that was low by
  paths, and the merge job still demands green required checks.
- Negative: CodeQL flags the review job (`actions/untrusted-checkout`): it checks out the PR's head in a job that
  holds the Claude credential. Accepted, because the branch is in this repository, the PR is low by its paths
  right then, no step runs anything from the checkout, and the reviewer starts in an empty directory with the
  checkout as an extra directory and user settings only, so the PR's `.claude/`, `CLAUDE.md` and `.mcp.json` are
  never loaded. The alert is dismissed by the owner, not silenced in the workflow.
- Negative: tests and docs under paths with sensitive words (for example a test of the auth filter) are high.
  That's deliberate over-caution; the lists are widened or narrowed only by the owner's merge of this script.
- Negative: ROADMAP.md is high although it is a doc: it starts the next step when merged (ADR 0026).
- Not proven until merged: the pinned Claude CLI accepting `--allowedTools` with the default permission mode in
  `--print` mode, and the App's token merging under the `main` ruleset. A failure in either stops the run red
  and merges nothing.
- No release: only the factory repo changes; no plugin or parent version moves.
