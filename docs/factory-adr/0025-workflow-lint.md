# 0025. Lint every workflow with actionlint

- Status: Accepted
- Date: 2026-11-13
- Deciders: Noel Abi Abdallah

## Context
Three releases in a row shipped a service workflow that GitHub would not load: 0.17.0 and 0.18.0 had an unquoted
`spec: ` in a step name (not valid YAML), and 0.19.0 used `${{ runner.temp }}` in job-level `env`, where GitHub
doesn't allow the runner context. Factory CI tested the runner script with a stand-in agent and checked
the workflows only with grep and PyYAML, so neither defect showed until a real service repo tried to run them
(demo-service, 2026-11-12). B2's own workflow nearly had the second defect too.

## Decision
- `ci/lint-workflows.sh` runs **actionlint** (pinned to 1.7.12, sha256-verified, like the other CI tools) on every
  workflow of the factory and both templates, in factory CI. It checks the workflow schema, expressions and which
  contexts are allowed where.
- The script first lints a known-bad file (the runner context in job-level `env`) and fails if actionlint accepts it,
  so a broken or misconfigured linter can't pass silently.
- Its shellcheck and pyflakes checks of `run:` scripts are off for now. Turning them on means first fixing what they
  find in the existing workflows, so that is a separate change.
- java-pipeline 0.19.1 fixes 0.19.0's workflow.

## Alternatives considered
- **Only stricter grep checks in `check-supply-chain.sh`:** each catches one known mistake and misses the next one.
- **Run the workflows on a scratch repo in CI:** the real test, but it needs a repo and tokens on every PR. B3's
  provisioning plus an acceptance run covers that once per release.

## Consequences
- Positive: a workflow GitHub would reject fails factory CI on the PR that introduces it.
- Negative: actionlint is pinned by hand (Dependabot can't bump it); the B7 maintenance agent should watch it.
- Negative: actionlint knows the inputs of popular actions; an action whose inputs it doesn't know yet may need
  its config file.
