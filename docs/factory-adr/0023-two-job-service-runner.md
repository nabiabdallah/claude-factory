# 0023. The service runner hands over a bundle and gates on a fresh checkout

- Status: Accepted
- Date: 2026-11-12
- Deciders: Noel Abi Abdallah
- Implements: step B2a of [ADR 0020](0020-self-running-factory.md); fixes the weakness named in [ADR 0022](0022-headless-factory-steps.md)
- Amends: [ADR 0018](0018-headless-feature-runs.md), [ADR 0019](0019-intake-idea-to-spec.md)

## Context
`factory-feature.yml` (ADR 0018) ran resolve, agent, gate and publish as steps of one job, from the checkout the
agent had just had full write access to. An agent that rewrote `.github/scripts/factory-run.sh` would pass its own
gate, and the rewritten `publish` would run with the job's write token. ADR 0022 closed this for the factory's own
steps with two jobs; the service runner still had it.

Building the fix showed one more trap: a job that checks out the base, unpacks the agent's branch and then runs
`.github/scripts/factory-run.sh` runs the agent's copy of it. The test with an agent that rewrites the runner caught
this before the first version was written into the workflow.

## Decision
`factory-feature.yml` and `factory-run.sh`, in both templates, become four jobs:
- **agent**: checkout without credentials, token that can't write, the Claude credential. Runs `resolve`, `tools`,
  `agent`, then `pack`: leftovers, commits and the report are checked, and a git bundle of the commits is handed
  over with the report. `mode`, `branch`, `base`, `base_branch` and `spec` are job outputs, set by `resolve` before
  the agent ran.
- **gate**: a fresh checkout of the base commit, `contents: read`. `unpack` checks the bundle (valid, starts from
  the base, commits present, report under 60 kB, branch and spec match what `resolve` produced), then `gate` runs
  the existing checks and `./mvnw verify`. It outputs the commit it verified.
- **publish**: a fresh checkout of the base, the write token, no build. It unpacks again, repeats the checks without
  the build (`FACTORY_GATE_BUILD=0`), refuses unless the commit is the one the gate verified, then pushes and opens
  the pull request.
- **report**: a checkout of the default branch, `issues: write`. Comments on the issue when any job failed, was
  cancelled or timed out. The reason travels as a job output, as text in the environment.

Both `gate` and `publish` copy the runner out of the checkout before `unpack` and run the copy
(`$RUNNER_TEMP/trusted-factory-run.sh`): after `unpack` the tree is the agent's.

The gate job is a separate job from publish because `./mvnw verify` runs the agent's code (its tests, its `pom.xml`
changes). That job holds no token that can write. The build there is a quality gate, not a security boundary:
code running in it could report anything about itself. The boundary is that the publish job runs no agent code, and
the pull request's own CI (a required check) builds the change again.

`ci/test-factory-run.sh` models the jobs as separate clones that share only the bundle and the report, and covers an
agent that rewrites the runner (and hands over its own bundle), history that doesn't start from the base, and a
publish of a commit the gate didn't verify.

The same release fixes a defect in the 0.17.0 and 0.18.0 workflow: the gate step's name contained `spec: ` unquoted,
so the file was not valid YAML and the workflow could not have started. Nothing had run it yet (the acceptance run
is part of B3). No factory check parses the workflow files, so CI would not have caught it; adding one is a
follow-up below.

## Alternatives considered
- **Two jobs, as ADR 0022:** the gate and publish would share a job, so the agent's `pom.xml` and tests would run
  next to the write token. Three jobs plus the report job cost a few runner minutes.
- **Run the gate's build in the agent job:** the agent's own code would be the judge of itself.
- **Check out the agent's tree in the publish job only for the spec file:** still needed for the spec checks; the
  trusted copy of the runner makes it safe.

## Consequences
- Positive: nothing the agent wrote runs with a token that can write, in service repos as in the factory.
- Positive: the failure comment is posted by trusted code, and a cancelled or timed-out run is reported too.
- Negative: services that copied the 0.17.0/0.18.0 runner must copy both files again (Upgrading note, 0.19.0).
- Negative: the run takes a few minutes longer: the checkout, download and setup of the extra jobs.
- Follow-up: a CI check that parses the workflow files (YAML) and lints them would have caught the quoting defect.
