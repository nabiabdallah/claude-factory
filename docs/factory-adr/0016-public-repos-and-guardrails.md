# 0016. Public repositories and repo guardrails

- Status: Accepted
- Date: 2026-11-08
- Deciders: Noel Abi Abdallah

## Context
Nothing mechanically stopped a direct push to `main`, a merge with red checks, a moved release tag or a committed
secret. On the free plan the rulesets API answers 403 "Upgrade to GitHub Pro or make this repository public" for
private repos, and secret scanning is also free only on public repos. Without protection, the #3 promotion PR's
checks (ADR 0012) were advisory.

Before going public, a pattern scan of every commit in claude-factory and payments-service (GitHub/AWS/Slack/OpenAI
tokens, private keys, JWTs, `password|secret|token = <value>`) found no secret. Most existing commits carry the
owner's personal email as author.

## Decision
- **Public:** claude-factory and payments-service become public; new services are created public (ONBOARDING
  step 5). Existing history is kept as is (rewriting it would change every SHA, breaking the commit-pinned image
  tags and the release tags); new commits use the GitHub noreply address.
- **No license:** no LICENSE file, `plugin.json` stays `UNLICENSED`: the code is readable, not reusable.
- **`ci/protect-repo.sh <owner/repo> <factory|service>`** applies, idempotently, with the owner's admin `gh`
  login (rulesets are matched by name: created if missing, replaced if present):
  - Ruleset `main` on the default branch: PR required with **0 approvals**, required checks from GitHub Actions
    with the branch up to date, no deletion or force push. Factory checks: `Template builds and new-project works`,
    `Kubernetes manifests render and match the schemas`; service checks: `verify`, `manifests`. Only repository
    admins bypass, in `pull_request` mode: they can merge a PR whose check is broken, but nobody pushes to `main`.
  - Ruleset `release tags` (factory): `java-pipeline-v*` and `factory-parent-v*` can be created but not updated
    or deleted, with no bypass (projects pin them, ADR 0015).
  - Secret scanning with push protection; Dependabot alerts and security updates; private vulnerability reporting
    (`SECURITY.md`); CodeQL default setup for Java and Actions.
  - Actions: fork-PR workflows wait for approval for all outside contributors; the default workflow token is
    read-only; the factory keeps "Actions may create PRs" on for `base-image.yml` (ADR 0009).
  - It refuses a repo that isn't public.
- **Tested without GitHub:** `ci/test-protect-repo.sh` runs in factory CI: the `--dry-run` requests are checked
  with jq against the rules above, the required check names against the real job names in the factory and
  template workflows, and the apply path against a fake `gh` (private repo refused; create vs update by name).
- java-pipeline and factory-parent are unchanged.

## Alternatives considered
- **GitHub Pro (about $4/month)** — private repos with rulesets, but no free secret scanning or CodeQL for private
  repos on a personal account.
- **An organization** — same feature limits on the free plan, plus moving repos and packages.
- **1 required approval** — the owner opens every PR with their own token and GitHub never lets an author approve
  their own PR, so every merge would need a bypass; the gate is the owner's merge plus green checks.
- **Classic branch protection** — works, but rulesets also cover tags and can be read and replaced as one JSON
  document by name.
- **Rewriting history to remove the email** — new SHAs everywhere; rejected by the owner.

## Consequences
- Positive: `main` changes only through a PR with green checks, including deploy promotions (ADR 0012); release
  tags are immutable; pushes containing known secret formats are blocked; vulnerable dependencies and code
  patterns raise alerts.
- Negative: everything in the repos, and the owner's email in existing commits, is public. GHCR images keep their
  own visibility, and GitHub Packages still needs `FACTORY_PACKAGES_TOKEN` to read the parent.
- Negative: CodeQL adds a few minutes of Actions per PR.
- Negative: a renamed CI job silently becomes a check that never reports and blocks every merge; the factory test
  ties the names to the templates, but a service that renames `verify` or `manifests` blocks its own merges until
  its ruleset is edited.
- Negative: the real apply isn't run in CI (it needs the owner's admin token); it's verified by hand once per repo
  with `gh api …/rulesets` and a PR with a red check.
- Amends ADR 0012's follow-up "branch protection (#1)".
