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

## Status (2026-11-07)

### Done
| Step | Result | Record |
|---|---|---|
| #2 Supply chain | Base image pinned to a digest; Actions pinned to SHAs; SBOM; Trivy image scan; cosign keyless signing and SBOM attestation (proven end to end on a throwaway repo); weekly base-image PR | ADR 0009, PR #2, factory-parent 1.3.0 |
| Spring Boot 4.1 | factory-parent 2.0.0 (Boot 4.1.2, Spring 7, Tomcat 11, Jackson 3); scan runs with no exceptions | ADR 0010, PR #3 |
| #5 Security defaults | https-only issuer (loopback http allowed), required `sub`, caller-isolation and per-caller idempotency checks in the spec template, reviewers and test-writer; java-pipeline 0.12.0 | ADR 0011, PR #4 |
| #3 Deploy safety | Base + staging/prod overlays pinned to commits on `main` (`newTag: unreleased` until promoted); promotion = PR, checked by `check-deploy.sh` (kubeconform, commit on main, migration rollout rule with a `recreate` component); `MigrationRolloutTest` in add-postgres; PDB `maxUnavailable: 1`; default-deny NetworkPolicy; java-pipeline 0.13.0 | ADR 0012, PR #5 |
| #6 Build hygiene | Maven Enforcer in factory-parent (Java 21+, Maven 3.9+, pinned plugins, no SNAPSHOT/banned/Java-22+ dependencies); JaCoCo floor 80% lines / 70% branches, raise-only; factory-parent 2.1.0, java-pipeline 0.14.0 | ADR 0013, PR #6, factory-parent 2.1.0 published |
| #4 Observability | Actuator on management port 8081 (probes, `/actuator/prometheus`), Prometheus metrics with latency histograms, OpenTelemetry traces over OTLP (staging 100%, prod 10%), raw URLs stripped from spans, trace ids in logs; NetworkPolicy opens metrics/OTLP only to `claude-factory/monitoring` namespaces; java-pipeline 0.15.0 | ADR 0014, PR #7 |
| #7 Factory as a product | Release tags `java-pipeline-vX.Y.Z` with GitHub Releases; new projects pinned to their plugin release (`ref`, `sparsePaths`); changelogs for the plugin and factory-parent, checked on every PR and release; `docs/ONBOARDING.md`; docs link check; java-pipeline 0.16.0 | ADR 0015, PR #8, tag `java-pipeline-v0.16.0` |

### Waiting on the owner
- Review payments-service PR #10 (spec 0005).
- After 2.0.0 is published, Dependabot will open a parent-upgrade PR in payments-service that fails without
  the ADR 0010 code changes. Recommendation: close it, unless the owner wants payments-service upgraded.
- #1: the owner chose public repositories. Open decisions (details in `docs/plans/01-repo-guardrails.md`):
  1. Owner email in existing commits: accept it (no history rewrite) and use the noreply address from now on?
  2. payments-service: public too, or keep it private (then it gets no protection)?
  3. License: keep all-rights-reserved (no LICENSE), or add one (e.g. MIT / Apache-2.0)?
  4. Required PR approvals: recommendation 0 (PR + required checks, admin bypass only), because the owner
     authors the PRs and can't approve their own.
  5. CodeQL default setup: on or off (on adds a few minutes of Actions per PR)?

### Next, in the owner's approved order
1. **#1 Repo guardrails.** Public repos, rulesets on `main` and release tags, secret scanning, once the
   decisions above are made. Branch
   protection is what makes the #3 promotion-PR review mechanically required.

### After #1
Each new pipeline plugin gets its own plan for the owner's OK:
- A **frontend** pipeline, to complete the software.
- A **Python backend pipeline** for quant research.

Also planned: a standard intake step (idea → spec → owner approval).

### Waiting for a real cluster
Follow-ups from ADRs 0009, 0012 and 0014 that need a cluster to build or test:
- Admission policy that verifies the cosign signature at deploy time (policy-controller or Kyverno). ADRs 0009, 0012
- A CD job. ADR 0012
- GitHub Environments for staging/prod. ADR 0012
- Ingress/Gateway. ADR 0012
- Real egress CIDRs to replace the open 443/5432 egress. ADR 0012
- HPA. ADR 0012
- The real OpenTelemetry Collector address (until then spans are dropped). ADR 0014
- Dashboards and alerts, PodMonitor. ADR 0014
- JDBC and outbound-client spans, exemplars, OTel logs. ADR 0014

## Ideas (not yet approved)
Enhancements the owner proposes go here. Each moves to "Next" once the owner approves it.
- (none yet)

## Working notes (this machine)
Moved to the troubleshooting section of [ONBOARDING.md](ONBOARDING.md#troubleshooting-this-machine-wsl--the-claude-code-sandbox).
