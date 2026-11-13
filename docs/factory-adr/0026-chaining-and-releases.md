# 0026. Chaining and releases: merges start the next thing

- Status: Accepted
- Date: 2026-11-13
- Deciders: Noel Abi Abdallah
- Implements: step B4 of [ADR 0020](0020-self-running-factory.md)

## Context
After B0–B3 the factory can run a step or a feature unattended, but every hop between runs still waits for the
owner: saying "go" for the next step, putting `factory:build` on an issue after its spec merges, closing and
reopening a bot PR so CI starts, and pushing a tag after a version bump (0.17.0 never was tagged; 0.19.0–0.19.2
were tagged by hand on 2026-11-13).

Two GitHub rules shape the design. An event caused by a workflow's `GITHUB_TOKEN` starts no other workflow: a
label, a pushed tag or an opened pull request stays silent. The one exception is `workflow_dispatch` (and
`repository_dispatch`): a workflow may dispatch another with `GITHUB_TOKEN` and `actions: write`.

## Decision
- **Next step (factory).** `factory-chain.yml` runs when a merge changes `docs/ROADMAP.md` (every step's PR ticks
  its row), once a day, and by hand. `factory-chain.sh next-step` dispatches `factory-step.yml` for the first
  unfinished step unless: `FACTORY_PAUSED` is `true`; a `factory/step-*` PR is open; the step's branch exists; a
  step run is queued or running; or the last step run did not succeed on this same commit. The last rule keeps the
  daily schedule from re-running a step that stopped for a reason nothing has fixed. Each "no" is a green run
  whose summary says why. It uses `GITHUB_TOKEN` only (`actions: write`, no contents write, no App key).
- **Release tags (factory).** `release-tag.yml` runs when `plugin.json` or factory-parent's `pom.xml` changes on
  `main`. For each component whose `<component>-v<version>` tag doesn't exist, and whose changelog has that
  section, `factory-chain.sh release` creates the tag on the merged commit with the **factory App's token**, so
  `release-plugin.yml` and `publish-parent.yml` start as they do for a hand-pushed tag. A `-SNAPSHOT` version is
  not tagged. A failed tag lookup fails the run and is never read as "no tag".
- **Approved spec → build (services).** A new `factory-chain.yml` in both templates runs on pushes to `main` that
  touch `docs/specs/`. `factory-run.sh chain` looks for a spec that this push made `- Status: Approved`, and for
  the merged pull request of the pushed commit: only a branch `factory/spec-<n>` of the same repo counts, and `<n>`
  is the issue. It then adds `factory:build` to the issue and dispatches `factory-feature.yml` with the issue
  number and the label. It starts nothing when paused, when the issue is closed or already has the label, or when
  `factory/issue-<n>` exists.
- **`factory-feature.yml` accepts `workflow_dispatch`** (issue, label). A dispatched run reads the issue from the
  API and skips the "may the sender push" check: GitHub lets only writers and workflows with `actions: write`
  dispatch. Everything after `resolve` is unchanged: the spec's text still comes from the default branch, and the
  gate still runs on a fresh checkout (ADR 0023).
- **CI on the runner's pull requests (services).** The publish job dispatches `ci.yml` on the branch it pushed
  (`actions: write`), and `ci.yml` accepts `workflow_dispatch`. The check runs land on the pull request's head
  commit, so the close-and-reopen is gone without a token or the App in each service. `FACTORY_PR_TOKEN` still
  works as before; with it nothing is dispatched.
- **Services do not use the App.** Everything above runs on each service's own `GITHUB_TOKEN`. The App stays the
  factory repo's identity (step PRs, release tags). B3 adds services to the App's installation, which has no
  effect today and can be skipped.
- Tested by `ci/test-factory-chain.sh` (new) and `ci/test-factory-run.sh`, both with a fake `gh`.

## Alternatives considered
- **Put the App (or a token) in every service and let labels and PRs trigger workflows the normal way:** every
  service would hold the App's key or a long-lived token. Dispatch needs neither.
- **Tag inside `release-plugin.yml` on a push to `main`:** one workflow fewer, but the release workflows would
  have two entry points to keep equal, and a hand-pushed tag (the documented fallback) would take a different path.
- **Dispatch the next step on every push to `main`:** a typo fix would start a step. The roadmap changes exactly
  when a step finishes.
- **Retry a failed step every day:** it spends the subscription on a failure that needs a person. B6 and B7 add the
  usage brake and the inbox.
- **Chain any approved spec to a build:** a hand-written spec has no issue to build from. The owner labels one.

## Consequences
- Positive: merging a step's PR starts the next step; merging an approved spec PR starts its build; merging a
  version bump publishes the release. The owner's part is review and merge.
- Positive: service PRs get CI without a second token.
- Negative: merging **this** step starts B5 and tags java-pipeline 0.20.0 by itself. Set `FACTORY_PAUSED=true`
  first to hold the queue (it doesn't hold release tags).
- Negative: a dispatched CI run tests the branch head, not the merge with `main` that a `pull_request` run tests.
  The `main` ruleset requires an up-to-date branch, so the two agree when it matters.
- Negative: anyone who can push a branch `factory/spec-<n>` and get its PR merged can start a build for issue
  `<n>`. They could also add the label, and the owner merges every PR.
- Negative: who may create release tags is still unrestricted (ADR 0020, B0). Restricting creation to the App
  needs a ruleset change, which only the owner makes; it is listed in the roadmap.
- Not proven until merged: GitHub accepting the dispatches, and the acceptance run on demo-service (which first
  needs the 0.20.0 files).
