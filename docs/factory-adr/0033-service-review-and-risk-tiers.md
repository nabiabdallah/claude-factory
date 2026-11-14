# 0033. Services review every pull request independently, and merge only low-risk ones

- Status: Accepted
- Date: 2026-11-14
- Deciders: Noel Abi Abdallah
- Amends: [ADR 0027](0027-risk-tiers-and-auto-merge.md) (risk tiers and auto-merge, so far in claude-factory only)
- Amended 2026-11-14 (java-pipeline 0.21.1): the first real review failed at once. The prompt began with the agent
  file's `---` front matter and the CLI read it as an option. The prompt is now the file's body behind a plain
  first line, in the factory's reviewer too, and both tests' stand-in reviewers reject a prompt that starts with
  `-`, as the CLI does.

## Context
market-rates PR #5, the factory's first real feature (38 files, +2477), reached the owner with 0 reviews and no
risk label. The pipeline's `code-reviewer` had reviewed it, but inside the run that wrote the code, and its verdict
reached the owner as the builder's own PR description. A fresh `code-reviewer` run from a session then said
REQUEST CHANGES: a fourth asset failed startup (against the spec's "config only"), and provider errors leaked
the URL with the symbol into spans, a leak the in-run reviewer had flagged and accepted an ineffective fix for.
Risk tiers and the independent reviewer existed only in claude-factory (ADR 0027); the templates shipped
`ci.yml`, `factory-chain.yml` and `factory-feature.yml`.

## Decision
The owner approved the three recommended choices on 2026-11-14.
- **Every pull request from a branch of the repository is reviewed, whatever its tier.** `factory-review.yml`
  runs when CI passes on a pull request (or by hand). Same isolation as ADR 0027: scripts from the default
  branch, the head checked out as data, the reviewer in an empty directory with `Read Grep Glob` only, user
  settings only, a 400 kB diff cap, a last line that must be exactly `VERDICT: APPROVE` or `VERDICT: REQUEST
  CHANGES`, and the diff treated as data. The brief is `agents/code-reviewer.md` of the plugin release the
  service pins in `.claude/settings.json`, cloned at that tag. Never for a branch from another repository: the
  job holds the Claude credential.
- **The review is posted on the pull request**, marked and headed "Independent review (advisory)", and replaced
  on each new head. Only the Actions bot's own marked comment is replaced.
- **Service path lists** (`.github/scripts/risk-tier.sh`, the only place they live): low is `README.md`, other
  Markdown under `docs/`, files under `src/test/`, and Dependabot patch or minor bumps of `pom.xml` and pinned
  actions. High is everything else, in particular `src/main/`, `docs/specs/` (a merged approved spec starts a
  build), `CLAUDE.md`, `.claude/`, ArchUnit tests, `deploy/`, migrations, `.github/`, the build, a factory-parent
  bump, any path with a security, money or credential word, and any path it doesn't know.
- **Only a low pull request merges by itself**, as in ADR 0027: the reviewed sha, still low by its paths, no
  `risk:high` label, every required check of `main`'s ruleset green, verdict approve. Merged as the factory's App
  when the repository has `FACTORY_APP_KEY` (so the push to `main` starts workflows), else with the workflow's
  token. `FACTORY_PAUSED=true` stops reviews and merges.
- **A feature never merges by itself.** It changes `src/main/`; revisit once evals (A6) measure the reviewer.
- java-pipeline 0.21.0 ships `risk-tier.sh`, `risk-tier.yml` and `factory-review.yml` in both templates.
  `ci/check-supply-chain.sh` fails a template whose review job holds a GitHub token, the App or a write
  permission, uses the App's key outside the merge job's token action, or whose copies differ.
  `ci/test-service-review.sh` tests both templates in factory CI. Provisioning creates `risk:low`.

## Alternatives considered
- **Review low pull requests only, as in the factory:** the feature, the pull request that most needs other eyes,
  would get none.
- **Make the review a required check:** it would block merges whenever the reviewer is wrong, out of usage or
  down, and needs a ruleset change in every service. Advisory plus the owner's merge is enough for high PRs.
- **Auto-merge features on APPROVE:** the reviewer is unmeasured, and PR #5 shows a reviewer passing real defects.

## Consequences
- Positive: every feature reaches the owner with a review from a run that did not write it.
- Positive: docs, test-only and minor dependency PRs in services stop waiting for the owner.
- Negative: one reviewer run per green CI run on every pull request; the ledger (ADR 0030) counts factory runs only,
  so service reviews are not counted yet.
- Negative: code scanning flags the review job (`actions/untrusted-checkout`) in each service, as in the factory;
  the owner dismisses it per repository.
- Negative: existing services need the three files and the `ref` (the changelog's Upgrading note).
- Not proven until a service runs it: the reviewer's clone of the plugin tag and the App merge under a service's
  ruleset. A failure stops the run red and merges nothing.
