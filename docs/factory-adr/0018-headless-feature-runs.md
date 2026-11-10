# 0018. Unattended feature runs: a labelled issue goes through the pipeline to a PR

- Status: Accepted
- Date: 2026-11-10
- Deciders: Noel Abi Abdallah

## Context
The pipeline ran only in an interactive Claude Code session on the owner's machine. Nothing could start it
without him at the keyboard, and the only thing stopping a session from ending on a red build was the Stop hook,
which gives up after 3 attempts. The audit of 2026-11-10 put this first among the gaps (roadmap step A2).

An unattended run changes the risks. Nobody answers a permission prompt, so the agent runs without them. The
text that starts the run (an issue) can be written by anyone once the repos are public (ADR 0016). And the
agent's own report that the build is green can't be the gate.

## Decision
- **Trigger:** the label `factory:build` on an issue in a service repo starts `.github/workflows/factory-feature.yml`
  (in both templates). The phases live in `.github/scripts/factory-run.sh` so they can be tested without GitHub.
- **What may be built:** only an approved spec. The issue just names a path (`docs/specs/NNNN-name.md`); the
  spec is read from the default branch and must say `- Status: Approved` and have numbered acceptance criteria.
  Issue text never reaches a command line or the agent's prompt. The person who put the label on must have write
  access to the repository.
- **Which pipeline:** the plugin release the project is pinned to (ADR 0015), cloned at that tag and loaded with
  `--plugin-dir`, run by a Claude Code CLI pinned to an exact version in `factory-run.sh`. The prompt is
  `/java-pipeline:new-feature …`; the skill's new "Headless runs" section replaces every "wait for the owner"
  with "stop and report".
- **What the agent can reach:** the checkout keeps no credentials and the agent step gets no GitHub token: it
  can't push, open a PR or call the API. It gets the Claude credential and the read-only packages token. It runs
  with `bypassPermissions` and a spending cap (`FACTORY_MAX_BUDGET_USD`, default 25).
- **Gate, run by the workflow after the agent:** something was committed and nothing left uncommitted; a report
  exists; no change to CI or the runner, `.claude/`, `CLAUDE.md`, specs, `ArchitectureTest`, `archunit.properties`,
  the Maven wrapper, `.gitignore`, `.trivyignore.yaml` or a deploy overlay; no deleted test; no `pom.xml` line that
  loosens a build rule (ADR 0013); then `./mvnw verify`. Any failure fails the run and opens no PR.
- **Publish:** a later step pushes `factory/issue-<n>` and opens a PR whose body is the agent's report and
  `Closes #<n>`, then comments on the issue. On failure the issue gets the phase and the reason instead. The
  report, the agent's result and the build log are kept as the `agent-run` artifact.
- **Secrets:** `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) or `ANTHROPIC_API_KEY`; `FACTORY_PACKAGES_TOKEN`
  as for CI. Optional `FACTORY_PR_TOKEN`: GitHub doesn't start workflows on a PR opened with the workflow's own
  token, so without it the owner closes and reopens the PR to start CI.
- **Tested without GitHub, Maven or a credential:** `ci/test-factory-run.sh` (fake `gh`, a stand-in agent, a
  local bare remote) covers who may start a run, which specs count, each thing the gate refuses, the red build,
  and what is pushed and posted. `ci/check-supply-chain.sh` checks the CLI pin, the credential-free checkout,
  that the agent step has no GitHub token, that no `run:` interpolates an expression, and that both templates
  carry the same runner.
- java-pipeline 0.17.0.

## Alternatives considered
- **`anthropics/claude-code-action`** — less code, but it gives the agent a GitHub token and decides itself how
  branches, comments and PRs are made; the split between "agent works" and "workflow publishes" is the point here.
- **Let the agent open the PR** — one step fewer, but then a prompt-injected or confused agent can push anything
  the token allows.
- **Build straight from the issue text** — no spec file needed, but the owner's approval of the spec would be
  skipped and outside text would reach the agent. Drafting a spec from an idea is the intake step (A3).
- **A permission allowlist instead of `bypassPermissions`** — tighter, but an unattended run that meets one
  unlisted command stops half-done. The limits are the missing token, the gate and the PR review instead.
- **Fail the session from the Stop hook** — the hook can't fail a run, only block or allow a stop.

## Consequences
- Positive: a feature costs the owner an approved spec, a label and a review; the laptop can be off.
- Positive: a red build, a weakened rule or a touched protected file can't reach a PR, whatever the agent reports.
- Negative: the real agent call is not exercised in factory CI (it needs a credential and costs money). It is
  proven by hand: one labelled issue on a fresh service, once per plugin release that changes the runner.
- Negative: a feature that truly needs a protected file changed (a new CI secret, a Kubernetes overlay) can't be
  finished unattended; the report says so and the owner makes that change.
- Negative: the CLI version is pinned by hand; Dependabot can't bump it.
- Negative: existing services don't get the workflow by themselves (changelog 0.17.0, Upgrading).
- Negative: each run spends Claude usage; the cap bounds one run, not the number of runs.
