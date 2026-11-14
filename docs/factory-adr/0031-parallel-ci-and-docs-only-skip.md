# 0031. Factory CI runs in parallel jobs and skips the builds for docs-only changes

- Status: Accepted
- Date: 2026-11-14
- Deciders: Noel Abi Abdallah

## Context
The required check "Template builds and new-project works" took 486 s on run 43519014144 (PR #31, a roadmap-only
change); every other check took 4 to 90 s. Three causes:
- Every step ran in sequence in one job: five Maven-heavy smoke tests, one after another.
- The job ran in full for every pull request, whatever it changed. Roadmap and ADR pull requests are frequent.
- The `main` ruleset requires an up-to-date branch, so each merge to `main` costs every open pull request a rerun.

Two things limit the fix. The ruleset requires two status checks by name (`ci/protect-repo.sh`), and a ruleset
change is the owner's alone. And the smoke tests used to build on each other: add-postgres changed `ci-skeleton`,
and the deploy gate, add-resource-server and the build rules then ran on that same project.

## Decision
The owner approved the plan and its three choices on 2026-11-14.
- **Parallel jobs.** `ci.yml` has `scripts` (everything that needs no Maven build: the factory's scripts against
  fakes, release notes, docs links, workflow lint, the runner tests on the templates) and five build jobs:
  `templates`, `new-project`, `postgres`, `resource-server`, `build-rules`. Each build job installs
  factory-parent and creates the projects it needs; the jobs share nothing.
- **The required names stay.** Only two jobs carry a `name:`. `template` ("Template builds and new-project
  works") now waits for all the others, runs with `if: always()`, and passes only when `changes` and `scripts`
  succeeded and each build job succeeded or was skipped for a docs-only change. The ruleset is untouched, and
  `ci/test-protect-repo.sh` still checks that the named jobs are exactly the required checks.
- **Docs-only pull requests skip the build jobs.** The `changes` job lists the pull request's paths (the merge
  commit against its first parent, renames listed under both paths). When every path is under `docs/` or is a
  Markdown file in the repo root, only `scripts` and `manifests` run. Markdown under `plugins/` is not docs: it
  includes skills and agent prompts, which change behaviour. No paths, a diff that can't be made, or any other
  path means a full run. A push to `main` is always a full run.
- **The up-to-date rule stays.** It is what makes a green pull request mean green on `main`.
- The two decisions live in `.github/scripts/ci-changes.sh`, tested by `ci/test-ci-changes.sh`, which also checks
  the workflow's wiring.

## Alternatives considered
- **`paths-ignore` on the workflow:** a required check that never reports blocks the pull request for good.
- **Rename or add required checks:** a ruleset change for no gain; one verdict job keeps the ruleset as it is.
- **Share generated projects between jobs as artifacts:** saves about a minute of repeated setup per job and adds
  an ordering between jobs, which is what made the single job slow.
- **Drop the up-to-date rule:** the cheapest speed-up and the only one that lets a broken `main` through.

## Consequences
- Positive: the wait is the longest job, not the sum. Expected about 3 minutes for a full run and under 1 minute
  for a docs-only pull request; neither is measured yet, the first runs will tell.
- Positive: with risk tiers (ADR 0027), a `risk:low` docs pull request can merge by itself within about a minute.
- Negative: more runner minutes in total, since each build job repeats the setup and the parent install. The repo
  is public, so the minutes are free.
- Negative: a docs-only pull request is not proof that the templates still build. `main` runs the full set after
  the merge, so a break shows there, one merge late.
- Negative: the build rules now run on a fresh `ci-skeleton`, no longer on one that had Postgres and the resource
  server added. The rules under test are factory-parent's and don't depend on either.
- The pull request's own copy of `ci-changes.sh` decides its scope, as its own `ci.yml` always decided what CI
  runs. Both are under `.github/`, so a change to either is `risk:high` and waits for the owner.
