# 0024. Service provisioning in one workflow run

- Status: Accepted
- Date: 2026-11-12
- Deciders: Noel Abi Abdallah
- Implements: step B3 of [ADR 0020](0020-self-running-factory.md)

## Context
A new service takes the owner about ten manual steps (ONBOARDING 4, 5 and 7): scaffold, create the repo, two
packages secrets, the Claude token, three labels, `protect-repo.sh`, and in future adding it to the factory's App.
On 2026-11-12 the auto-mode check blocked the session from creating a public repo and from reading the packages
token: rightly, since the session acted as the owner.

Creating a repo on a personal account needs a user token: a GitHub App can only create repos in an organisation.
GitHub's documentation lists `POST /user/repos`, Actions and Dependabot secrets, rulesets, code scanning setup and
`PUT /user/installations/{id}/repositories/{id}` as available to fine-grained personal tokens.

## Decision
- **`new-service.yml`** (`workflow_dispatch`: name, package, template), with phases in
  `.github/scripts/new-service.sh`:
  - **check:** kebab-case name, at most 40 characters; a package like `com.example.x`; a known template; the repo
    must not exist; `claude-factory` and `payments-service` are refused.
  - **scaffold:** `new-project.sh` from the **latest `java-pipeline-v*` tag**, checked out as a worktree, so the
    project pins a release and never an untagged `main`. Its `./mvnw verify` must be green, and the commit is
    authored by the factory's bot.
  - **create:** the public repo, then a push of `main`.
  - **configure:** `FACTORY_PACKAGES_TOKEN` for Actions and Dependabot and `CLAUDE_CODE_OAUTH_TOKEN`, all copied
    from claude-factory's secrets on stdin and never printed; the labels `factory:spec`, `factory:build` and
    `risk:high`; the repo added to the App's installation; then `ci/protect-repo.sh <repo> service`.
- **The admin token is a fine-grained token of the owner's (`FACTORY_ADMIN_TOKEN`),** scoped to all
  repositories with Administration, Contents, Secrets, Dependabot secrets, Issues and Workflows read/write, plus
  the account permission for App installation access. It is stored **only in a `provisioning` environment
  restricted to `main`**. So it reaches only workflow code that is on `main`, and `.github/` changes there are
  `risk:high`, which only the owner merges. A headless step's branch can't use it.
- Because this token could change rulesets everywhere, `new-service.sh` and its workflow are protected files.
  ADR 0020's never-list applies: provisioning only creates new repos and configures them, and never edits an
  existing one.
- The factory-step gate (ADR 0022) now also treats the templates' `.github/` and ADRs 0017 and 0020–0024 as
  protected. The B2a run showed that template workflows had slipped through.
- Tested by `ci/test-new-service.sh` (fake `gh`, a stand-in `new-project.sh`, a local remote).

## Alternatives considered
- **A GitHub organisation, so the App could create repos:** no user token at all, but it moves the repos and breaks
  the marketplace and package references (ADR 0020). Revisit if more people join.
- **A required reviewer on the environment:** you'd approve every provisioning run. That's safer, but provisioning
  is rare and deliberate, and the main-only restriction already keeps the token away from agent code. You can add
  the reviewer in the environment settings at any time, without a code change.
- **A classic token with `repo` scope:** broader, and it doesn't expire by default.

## Consequences
- Positive: a new service is one dispatch, and it starts protected, with the App installed and the labels ready
  for unattended runs.
- Negative: the owner creates the fine-grained token and the environment once, sets `FACTORY_PACKAGES_TOKEN` as a
  claude-factory secret, and renews the token when it expires.
- Negative: new services get the latest *tagged* release, so an untagged version bump (as 0.19.0 is until it's
  tagged) isn't used yet. B4 tags on merge.
