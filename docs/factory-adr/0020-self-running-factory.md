# 0020. Self-running factory: own identity, chained steps, low-risk auto-merge

- Status: Accepted
- Date: 2026-11-12
- Deciders: Noel Abi Abdallah
- Amends: [ADR 0017](0017-autonomous-mode.md)

## Context
ADR 0017 cut the owner's approvals per step to one trigger and one review, yet the owner still steps in several
times per step. An audit on 2026-11-12 traced this to three causes, not to the agents:
- **No identity of its own.** The factory acts with the owner's `gh` login, email, Claude subscription and
  `~/.m2` token. Every privileged action is therefore the owner's, and both the rules and Claude Code's
  auto-mode check require his yes for it (repo creation and reading the packages token were blocked on 2026-11-12).
- **It runs on the owner's laptop,** inside a sandbox built for interactive use: no `gh`, Maven Central 502s,
  no Docker, blocked release assets, a read-only `.git/config`.
- **Every gate is a person.** There are no rulesets on `claude-factory`, so "never merge" depends on the agent
  behaving. Steps start on "go", specs need a manual relabel, bot PRs need a close/reopen to start CI, and
  releases are tagged by hand (0.17.0 never was).

The rest is a lack of provisioning (each service is set up by hand) and of maintenance (Dependabot PRs, plugin
drift and expiring exceptions wait until the owner notices them).

## Decision
The owner's answers on 2026-11-12:
1. **The factory gets its own GitHub identity:** a GitHub App, plus a fine-grained token where an App can't act
   (repo creation on a personal account). Workflows mint short-lived tokens; no session uses the owner's login.
2. **Low-risk PRs merge without the owner.** A workflow sets the tier from the PR's changed paths, never from
   the agent's own claim. Low: docs, test-only changes, Dependabot patch/minor updates, and feature PRs that
   touch no high path. High: security/auth, money, idempotency, migrations, `deploy/`, build rules in
   `pom.xml`, workflows, `.claude/`, `CLAUDE.md`, `ArchitectureTest`, the tier classifier, major dependency
   bumps, and any path the classifier doesn't know. A low PR merges once required checks pass and an
   independent code-reviewer run on the final diff says APPROVE.
3. **Steps chain without a "go".** Merging a step's PR, or a daily schedule, starts the next queued step.
   Merging an approved spec starts its build. Merging a version bump tags and publishes the release. Only one
   step is open at a time.
4. **The spending brake is the owner's Claude subscription limit,** not a dollar cap. Runs use the
   subscription token. When a run hits the usage limit, dispatch pauses until the limit resets and the inbox
   says so. The per-run `FACTORY_MAX_BUDGET_USD` stays as a guard against a runaway run.
5. **Everything above happens only in GitHub Actions workflows,** gated and logged, never from an interactive
   session. The never-list for any session or workflow becomes: merge a high-risk PR; change rulesets, the
   tier classifier, the App's permissions or the secrets' sources; delete a repo; force-push; push to `main`
   outside a merged PR; touch `payments-service` unless the owner asks.
6. **Enforced by GitHub, not by the agent's behaviour.** Rulesets on `main` and on release tags, with required
   checks, come first (step B0). Nothing else here starts until they're in place.

The steps are B0–B7 in the roadmap's autonomous queue, ahead of A4.

## Alternatives considered
- **Keep per-action approval (ADR 0017 as it stands):** safest, but the owner stays the bottleneck, and most of
  what he approves is mechanical.
- **Let the agent merge anything green:** removes the last human review of security, money and deploy changes.
  Rejected.
- **A free GitHub organisation, so the App can create repos too:** cleaner identity, but it moves the repos and
  breaks the `nabiabdallah/claude-factory` marketplace and package references. Revisit if the fine-grained
  token proves awkward.
- **A dollar cap per day:** the owner's subscription already limits usage, and an API-key budget isn't in use.

## Consequences
- Positive: the owner approves specs, merges high-risk PRs, grants permissions once, and reads a weekly digest.
- Positive: provisioning a service and the A2/A3 acceptance run become workflows, not checklists.
- Negative: a wrong tier can merge a bad change unseen. Mitigations: unknown paths count as high, classifier
  changes are high, and the weekly digest lists every auto-merge.
- Negative: factory runs share the owner's subscription limit with his own sessions. A busy queue can leave him
  short; he pauses the queue with the `FACTORY_PAUSED` variable.
- Negative: creating the App, running `protect-repo.sh` and `claude setup-token` stay manual; GitHub and Claude
  only let the account owner do them.
