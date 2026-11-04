# Factory roadmap

Read this first in every new session. Then read `CLAUDE.md`, and for history, the ADRs in `docs/factory-adr/`
and `~/dev/factory/BOOTSTRAP-LOG.md`. Update this file in the same PR that finishes a step.

## Goal
Make claude-factory a production-ready software factory: agents take a spec through tests, implementation,
review and a PR, and the owner approves. The work is on the factory itself. `payments-service` exists only to
validate the factory: don't port factory changes to it or build features on it unless the owner asks.

## How we work
- Run one session per step. Start the session with "Read docs/ROADMAP.md and continue", and end it when the step's PR merges.
- Plan before code. Write the step's plan to `docs/plans/<step>.md`, get the owner's OK, then implement. Delete
  the plan when the PR merges: the ADR and the PR description keep the reasoning.
- Send broad investigations to subagents so the main session stays small.
- Push, merge, tag, create a repo, or change GitHub settings only after the owner says yes.

## Status (2026-11-04)

### Done
| Step | Result | Record |
|---|---|---|
| #2 Supply chain | Base image pinned to a digest; Actions pinned to SHAs; SBOM; Trivy image scan; cosign keyless signing and SBOM attestation (proven end to end on a throwaway repo); weekly base-image PR | ADR 0009, PR #2, factory-parent 1.3.0 |
| Spring Boot 4.1 | factory-parent 2.0.0 (Boot 4.1.2, Spring 7, Tomcat 11, Jackson 3); scan runs with no exceptions | ADR 0010, PR #3 |

### Waiting on the owner
- Merge PR #3; then Claude tags and pushes `factory-parent-v2.0.0`, which publishes the parent.
- Delete the throwaway repo `nabiabdallah/ci-signing-check` and its GHCR package, and revoke its token if one
  was made for it.
- After 2.0.0 is published, Dependabot will open a parent-upgrade PR in payments-service that fails without
  the ADR 0010 code changes. Recommendation: close it, unless the owner wants payments-service upgraded.
- #1 needs a choice: GitHub Pro (about $4/month), public repos, or an organization.
- #4 needs a choice of stack: Prometheus + OpenTelemetry (default) or a vendor.

### Next, in the owner's approved order
1. **#5 Security defaults.** Fail startup when the issuer URI isn't https (outside the local profile). Make the
   reviewer agents check for one customer reaching another's data, the lesson from payments-service spec 0005. Add
   guidance on scoping idempotency keys to the caller.
2. **#3 Deploy safety.** The rolling update is hard-coded. Add a rule for migrations that can't run alongside the
   old version, environment overlays, a PodDisruptionBudget, a NetworkPolicy, and a gate before deploying `:main`.
3. **#6 Build hygiene.** Add Maven Enforcer to factory-parent (versions, banned dependencies) and a coverage floor.
4. **#4 Observability.** Expose metrics and tracing (only health is exposed today), using the stack the owner picks.
5. **#7 Factory as a product.** Plugin release tags, a changelog, and an onboarding guide.
6. **#1 Repo guardrails.** Branch protection and secret scanning, once the plan choice above is made.

### After #7
Each new pipeline plugin gets its own plan for the owner's OK:
- A **frontend** pipeline, to complete the software.
- A **Python backend pipeline** for quant research.

Also planned: a standard intake step (idea → spec → owner approval).

## Working notes (this machine)
- Maven Central often returns 502 through the sandbox proxy. Run Maven outside the sandbox
  (`source ~/.sdkman/bin/sdkman-init.sh; ./mvnw …`).
- `gh` must run outside the sandbox, because its config directory is denied. Its token has no `read:packages` or
  `delete_repo` scope, so check private GHCR images in a workflow in the repo.
- This machine can't download from release-assets.githubusercontent.com, so Trivy and cosign run only in CI. Get
  release asset sha256 values with `gh api repos/<o>/<r>/releases/tags/<t> --jq '.assets[]|.digest'`.
- Pull requests opened by Actions with `GITHUB_TOKEN` don't start CI. Close and reopen them.
