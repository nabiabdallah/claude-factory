# 0022. Factory steps run headless in GitHub Actions

- Status: Accepted
- Date: 2026-11-12
- Deciders: Noel Abi Abdallah
- Implements: step B2 of [ADR 0020](0020-self-running-factory.md)

## Context
Queue steps run in an interactive session on the owner's laptop, inside a sandbox that blocks `gh`, Maven
Central, Docker and GitHub release assets, so most steps need him to run something by hand. ADR 0018 already
runs service features headless in Actions. The factory's own steps need the same, with the factory's App
(ADR 0021) publishing the result.

Building it showed a weakness in ADR 0018's design: its gate and publish phases run `factory-run.sh` from the
checkout the agent just had full write access to. An agent that rewrote the script would pass its own gate, and
the rewritten publish phase would then run with the workflow's write token.

## Decision
- **`factory-step.yml`**, started by `workflow_dispatch` (input: a step id, or empty for the first unfinished
  one), with the phases in `.github/scripts/factory-step.sh`. One step at a time: it refuses while a
  `factory/step-*` PR is open, while the branch exists, or while the variable `FACTORY_PAUSED` is `true`.
- **Two jobs.** The **agent** job checks out without credentials and gets only the Claude credential. It runs
  "Read docs/ROADMAP.md and continue with step <id>" with the pinned CLI (the same pin as the service runner),
  `bypassPermissions` and the per-run budget, and hands over a git bundle of its commits plus its report as an
  artifact. The **publish** job checks out the base commit afresh, so it runs only code the owner merged. It
  gates the bundle (valid, starts from the base, commits present, no deleted `ci/test-*`, report under 60 kB),
  then mints an App token and pushes the branch and opens the PR. The step id, branch and base reach it as
  outputs of the agent job's first step, before the agent ran.
- **Protected files don't fail the run; they make the PR `risk:high`**: workflows and `.github/`, `.claude/`,
  `CLAUDE.md`, `protect-repo.sh`, the App's files, and ADRs 0017, 0020, 0021 and 0022. The PR lists them, and only
  the owner merges it (ADR 0020). B5 replaces this list with the full tier classifier.
- **The PR's CI is the build gate.** The agent runs the checks it touched before finishing (the new headless
  rules in `CLAUDE.md`), but the workflow doesn't rebuild everything: the ruleset already requires green
  factory CI to merge. A red PR stays open. Fix rounds come with chaining (B4).
- **A step that stops** (a decision only the owner can make, the never list) commits nothing. The run fails, and
  the job summary and the `agent-step` artifact say why. The inbox (B7) will collect these.
- Tested by `ci/test-factory-step.sh` with a stand-in agent, a fake `gh` and two separate clones, including an
  agent that rewrites the runner and history that doesn't start from the base.

## Alternatives considered
- **Copy ADR 0018's single job:** simpler, but it keeps the weakness above.
- **Run `./mvnw verify` and the whole factory CI in the gate:** that duplicates the PR's CI, which the ruleset
  already requires, and it's 10+ minutes on every run.
- **`anthropics/claude-code-action`:** rejected for the same reasons as in ADR 0018.

## Consequences
- Positive: a queued step needs no laptop: dispatch the workflow, review the PR.
- Positive: nothing the agent wrote runs with a write token.
- Negative: the run needs the `CLAUDE_CODE_OAUTH_TOKEN` secret in claude-factory, which only the owner can create
  (`claude setup-token`).
- Negative: the service runner (ADR 0018) still has the single-job weakness. Fixing it changes both templates and
  needs a plugin release, so it is a separate step (queued as B2a, done in [ADR 0023](0023-two-job-service-runner.md)).
- Negative: an agent that can't finish leaves only an artifact and a job summary, until B7.
