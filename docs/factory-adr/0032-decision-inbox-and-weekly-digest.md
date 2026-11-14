# 0032. Decision inbox and weekly maintenance digest

- Status: Accepted
- Date: 2026-11-14
- Deciders: Noel Abi Abdallah (step B7 of [ADR 0020](0020-self-running-factory.md); merging the PR approves it)

## Context
Unattended runs stop for reasons only the owner can settle (a failure, a usage limit, a decision), and they said so
in a job summary nobody opens. Dependabot PRs, expiring scan exceptions and the yearly Claude token waited until
the owner noticed. [ADR 0030](0030-usage-brake-and-ledger.md) left "the inbox says so" for this step.

## Decision
- **One inbox issue.** The open issue labelled `factory:inbox` ("Factory inbox") is the owner's queue; the first
  write creates and pins it (pinning is best effort: if GitHub refuses the token, the run says so and the issue
  still works). Every item is a comment, so there is one place to look.
- **A stopped run posts itself.** A new `inbox` job in `factory-step.yml` runs when a run that chose a step did not
  end in a PR. The comment names the step and outcome, the decision needed and a recommendation; for a failure it
  quotes the runner's reason as data (500 characters, backticks removed: the agent job wrote it).
  It uses the workflow's own token with `issues: write`, not the App's.
- **A weekly digest** (`factory-maintenance.yml`, Mondays, or by hand) comments: runs, cost and outcomes of the last
  seven days from the ledger; merged PRs and how many were `risk:low`; open PRs; Dependabot triage; `.trivyignore.yaml`
  exceptions expiring within 14 days or already expired; the Claude token against the repository variable
  `CLAUDE_TOKEN_EXPIRES` (flagged within 30 days, or when unset).
- **Dependabot triage is a recommendation, not an action.** A `risk:low` PR with green checks is merged by
  auto-merge ([ADR 0027](0027-risk-tiers-and-auto-merge.md)) already; the digest lists the rest with what to do (red
  checks: fix on its branch or close; `risk:high`: your review). The job has no write access to code or PRs, so
  nothing can be merged, closed or pushed by it. A fix by an agent stays a normal queued step.
- Logic is in `.github/scripts/factory-inbox.sh`, tested by `ci/test-factory-inbox.sh` with a fake `gh`.

## Not done here
- **Template-drift and plugin-upgrade PRs to services** (part of the roadmap's B7 row): they need the list of
  services and a write token on each, which touches the App's permissions (the owner's alone). There is one
  service today (demo-service); the digest says it isn't covered. Proposed as a follow-up once the real application
  exists, since the scope freeze ([ADR 0029](0029-scope-freeze-and-definition-of-done.md)) lets it decide.
- An agent that writes the Dependabot fixes. The recommendation names the fix; the owner or a queued step makes it.

## Consequences
- Positive: stops, usage pauses and maintenance debt arrive in one place with a recommendation.
- Negative: an inbox comment notifies only through GitHub's usual issue notifications; the owner must watch the issue.
- Negative: the `inbox` job runs for `failed` runs only when a step was chosen; refusals at `resolve` (paused, a PR
  open) are not stops and don't post.
