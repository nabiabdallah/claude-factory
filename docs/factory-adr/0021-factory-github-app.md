# 0021. The factory's GitHub App

- Status: Accepted
- Date: 2026-11-12
- Deciders: Noel Abi Abdallah
- Implements: step B1 of [ADR 0020](0020-self-running-factory.md)

## Context
Factory workflows act with `GITHUB_TOKEN`, and sessions act with the owner's `gh` login. A PR opened with
`GITHUB_TOKEN` doesn't start CI (the owner closes and reopens it), and anything done with the owner's login is the
owner's action, so it needs his yes. ADR 0020 gives the factory its own identity.

## Decision
- **One private GitHub App**, created by the owner from `ci/factory-app/manifest.json` through GitHub's manifest
  flow: `ci/create-factory-app.sh form <owner/repo>` writes a page that submits the manifest; after the owner
  clicks Create, `ci/create-factory-app.sh convert <code> <owner/repo>` exchanges the code. The private key goes
  straight from GitHub's response to the `FACTORY_APP_KEY` secret on stdin; it is never printed or written to
  disk. The client id and slug become the variables `FACTORY_APP_CLIENT_ID` and `FACTORY_APP_SLUG`.
- **Permissions: only what B1–B2 need.** Contents, pull requests, issues and workflows write, metadata read. No
  webhook, no events. These are narrower than ADR 0020's first sketch: no **administration** (it would let the
  App change rulesets, which nothing may do) and no **secrets**. Repo creation and secrets for B3 go through
  whatever B3 decides (an App can't create repos on a personal account anyway). Adding a permission is a manifest
  change in a PR, and the owner accepts it again on the installation.
- **Short-lived tokens only.** Workflows mint a token per job with `actions/create-github-app-token` (pinned by
  SHA, `client-id` + `private-key`). The key is passed to that action and nowhere else; `ci/test-factory-app.sh`
  checks this. The agent in a headless run never gets the token (ADR 0018 is unchanged).
- **The bot is the author.** `.github/scripts/bot-identity.sh` sets git's author to `<slug>[bot]` with its noreply
  address, or to `github-actions[bot]` when no App is configured.
- **First users:** `base-image.yml` uses the App when `FACTORY_APP_CLIENT_ID` is set (its PRs then start CI), and
  `factory-identity.yml` (manual) proves the setup: it opens a draft PR as the bot, waits for CI to start on it,
  then cancels that run and removes the PR and branch. Run it after creating the App and after rotating the key.
- Installed on claude-factory only for now. Services get it when B3 provisions them.

## Alternatives considered
- **A fine-grained personal token (`FACTORY_PR_TOKEN`):** it acts as the owner, lasts up to a year, and can't be
  told apart from him in the history. Kept only as the existing fallback in service templates until B3.
- **A machine user account:** a second account with a password, 2FA and long-lived tokens to look after, and
  repo-wide access through collaborator rights. An App's permissions are narrower and its tokens expire.
- **Administration permission now, to save a reinstall in B3:** rejected; it includes rulesets.

## Consequences
- Positive: bot PRs start CI; the history shows what the factory did, apart from the owner.
- Positive: a leaked token expires within an hour; the key itself sits in one secret of one repo.
- Negative: the owner creates and installs the App by hand (GitHub requires the account owner for both).
- Negative: `protect-repo.sh` still lets `GITHUB_TOKEN` create PRs in claude-factory (`can_approve_pull_request_reviews`).
  Once every workflow there uses the App, that switch can go off; that is a guardrail change, so it gets its own PR.
- Negative: the key doesn't rotate by itself. To rotate: generate a new key in the App's settings, store it with
  `gh secret set FACTORY_APP_KEY --repo nabiabdallah/claude-factory < key.pem`, delete the file and the old key,
  then run the identity check.
