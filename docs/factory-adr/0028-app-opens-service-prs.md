# 0028. The factory's App opens the service runner's pull requests

- Status: Accepted
- Date: 2026-11-14
- Deciders: Noel Abi Abdallah
- Amends: [ADR 0026](0026-chaining-and-releases.md) (CI on the runner's pull requests),
  [ADR 0024](0024-service-provisioning.md) (what provisioning copies into a service)

## Context
ADR 0026 (java-pipeline 0.20.0) had the service runner dispatch `ci.yml` on the branch it pushed, expecting the
checks to count on the pull request. The B4 acceptance run on demo-service (2026-11-13, spec PR #9, feature PR #10)
showed they don't:
- The dispatched run passes and its check runs sit on the head commit, but GitHub does not list them on the pull
  request and they don't satisfy the `main` ruleset's required checks. A second dispatch changed nothing.
- GitHub's own `pull_request` CI run for a PR opened with the workflow's token is created "awaiting approval" and
  never starts.
- Closing and reopening the PR as the owner starts a normal run, as before 0.20.0.

So every runner PR still needed a click, and 0.20.0's notes said otherwise. On claude-factory the same problem was
solved in B1/B2 by opening PRs as the factory's App (ADR 0021), and ADR 0021 already planned for services to get
the App when they are provisioned.

## Decision
The owner chose the App (2026-11-14).
- **The runner's publish job opens the pull request as the App.** When the secret `FACTORY_APP_KEY` is set, the job
  mints a token for its own repository (`actions/create-github-app-token`, client id from the variable or secret
  `FACTORY_APP_CLIENT_ID`) and pushes the branch, opens the PR and comments with it. The PR then starts CI like
  anyone's. Order of preference: the App, `FACTORY_PR_TOKEN`, the workflow's token.
- **No CI dispatch.** The publish job no longer dispatches `ci.yml` and loses `actions: write`. Opened with the
  workflow's token, the issue comment says to close and reopen the PR and how to end that. `ci.yml` keeps
  `workflow_dispatch` for runs by hand.
- **The key reaches only the publish job's token action.** That job checks out the base commit, runs the runner
  from a copy outside the agent's tree and builds nothing (ADR 0023). `ci/check-supply-chain.sh` fails a template
  where the agent or gate job can reach the key or the App's token.
- **Provisioning hands a service the App** (`new-service.sh`, function `give_app`): the repo joins the App's
  installation, then gets `FACTORY_APP_KEY` and `FACTORY_APP_CLIENT_ID` as secrets (the admin token has no
  Variables permission). The key is set only once the App is on the repo: a key without the installation would fail
  every publish job, while no key falls back to the workflow's token.
- **Existing services: the `Service app` workflow** (`service-app.yml`, the `provisioning` environment, main only)
  does the same for a named repo. If the admin token may not change the installation, the owner adds the repo by
  hand and runs it again; it then reads the installation's repositories with the App's own token to confirm.
  It refuses `claude-factory`, `payments-service` and any repo without `factory-feature.yml`.

## Alternatives considered
- **The publish job approves its own pending `pull_request` run:** no key in services, but unproven (GitHub may not
  let a workflow's token approve a run for its own PR), and it leans on behaviour GitHub documents nowhere.
- **Keep close-and-reopen:** nothing to build, a click per runner PR.
- **`FACTORY_PR_TOKEN` in every service:** works, but it is the owner's token, long-lived, and one more secret to
  renew per repo. Still supported for a service outside this factory's App.
- **A second App for services, without access to claude-factory:** limits what a leaked service key can reach.
  More to create and rotate; revisit when services have other writers than the owner.

## Consequences
- Positive: a runner PR starts CI by itself, so spec → merge → build → green feature PR needs no click.
- Positive: runner PRs and their comments are the bot's, like step PRs in claude-factory.
- Negative: **each service now holds the App's private key.** Whoever can run a workflow with secrets in a service
  (people with write access) could mint tokens for every repo in the installation, claude-factory included, with
  the App's permissions (contents, pull requests, issues, workflows). Rulesets still apply to those tokens: no push
  to `main` without a PR and green checks, no release tag outside the tag rules. Today the owner is the only
  writer everywhere. Rotating the key means setting it in claude-factory and re-running `Service app` per service.
- Negative: the key now passes through the provisioning script's environment (`APP_KEY`, to `gh secret set` on
  stdin), not only the token action. `ci/test-new-service.sh` checks it goes to that one step and is never printed.
- Negative: 0.20.0's claim is withdrawn; services on 0.20.0 keep a harmless dispatched CI run per runner PR until
  they take 0.20.1.
