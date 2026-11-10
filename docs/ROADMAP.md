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
  the plan when the PR merges: the ADR and the PR description keep the reasoning. Steps in the autonomous queue
  below skip the wait: their plan is the PR description and the owner's merge is the approval.
- Send broad investigations to subagents so the main session stays small.
- Merge, tag, push to `main`, create a repo, or change GitHub settings only after the owner says yes. Pushing a
  branch and opening a PR for a queued step needs no further yes (ADR 0017).

## Autonomous queue (ADR 0017)
The owner starts a session with "Read docs/ROADMAP.md and continue" (or just "go"). Take the first step below
that isn't done, bring it to a PR with green factory CI, and stop. One step per session, one PR per step. Tick
the step in the PR that finishes it. The steps come from the architecture audit of 2026-11-10 (java-pipeline
0.16.0): the factory is one strong production line, and these are what it lacks to work as a department.

| # | Step | Gap it closes | Done when |
|---|---|---|---|
| A1 | Autonomous-mode rules | Every action needed the owner's yes | This section, `CLAUDE.md` and ADR 0017 are merged |
| A2 | Headless runner | The pipeline only runs in an interactive session on the owner's machine: no trigger, no queue | A labelled issue in a service repo starts `new-feature` in GitHub Actions and ends in a PR; a red build fails the run (today the Stop hook gives up after 3 attempts and lets the session end). Needs from the owner: the Claude credential as a repo secret |
| A3 | Intake skill | Nothing turns an idea into a spec; the pipeline starts from a spec the owner co-writes | `/java-pipeline:intake <idea>` drafts a spec from `_template.md` with open questions listed, as a PR or issue the owner approves |
| A4 | Orchestrator and implementer split | The main session both conducts the stages and writes the code; a feature can't be resumed or split | An implementer agent; `new-feature` only orchestrates; per-feature state file so a new session resumes at the right stage |
| A5 | Domain rules out of the agents | Agents are hard-wired to banking (money, idempotency on transfers), which misfires on other software | Agents read a per-project profile; the banking checks become the `payments-example` profile; the skeleton gets a neutral one |
| A6 | Pipeline evals and metrics | CI tests scripts and templates, never agent behaviour; cost and cycle time aren't tracked | A benchmark spec runs through the pipeline on plugin changes and its result is recorded; each PR reports stages, attempts and reviewer findings |

Not queued yet (each needs its own plan and the owner's OK): more roles (security reviewer, end-to-end tester,
maintenance agent for Dependabot triage and template drift), a learning loop from reviewer findings back into
the agents, and the frontend and Python pipelines already listed under "After #7". GitOps, post-deploy checks
and the alert-to-issue loop wait for a real cluster.

Where the work runs: a cloud session can't download Maven dependencies, so factory CI on the PR is the judge
there. Use the owner's machine for steps that change the templates or factory-parent.

## Status (2026-11-05)

### Done
| Step | Result | Record |
|---|---|---|
| #2 Supply chain | Base image pinned to a digest; Actions pinned to SHAs; SBOM; Trivy image scan; cosign keyless signing and SBOM attestation (proven end to end on a throwaway repo); weekly base-image PR | ADR 0009, PR #2, factory-parent 1.3.0 |
| Spring Boot 4.1 | factory-parent 2.0.0 (Boot 4.1.2, Spring 7, Tomcat 11, Jackson 3); scan runs with no exceptions | ADR 0010, PR #3 |
| #5 Security defaults | https-only issuer (loopback http allowed), required `sub`, caller-isolation and per-caller idempotency checks in the spec template, reviewers and test-writer; java-pipeline 0.12.0 | ADR 0011, PR #4 |
| #3 Deploy safety | Base + staging/prod overlays pinned to commits on `main` (`newTag: unreleased` until promoted); promotion = PR, checked by `check-deploy.sh` (kubeconform, commit on main, migration rollout rule with a `recreate` component); `MigrationRolloutTest` in add-postgres; PDB `maxUnavailable: 1`; default-deny NetworkPolicy; java-pipeline 0.13.0 | ADR 0012, PR #5 |
| #6 Build hygiene | Maven Enforcer in factory-parent (Java 21+, Maven 3.9+, pinned plugins, no SNAPSHOT/banned/Java-22+ dependencies); JaCoCo floor 80% lines / 70% branches, raise-only; factory-parent 2.1.0, java-pipeline 0.14.0 | ADR 0013, PR #6, factory-parent 2.1.0 published |
| #4 Observability | Actuator on management port 8081 (probes, `/actuator/prometheus`), Prometheus metrics with latency histograms, OpenTelemetry traces over OTLP (staging 100%, prod 10%), raw URLs stripped from spans, trace ids in logs; NetworkPolicy opens metrics/OTLP only to `claude-factory/monitoring` namespaces; java-pipeline 0.15.0 | ADR 0014, PR #7 |
| #7 Factory as a product | Release tags `java-pipeline-vX.Y.Z` with GitHub Releases; new projects pinned to their plugin release (`ref`, `sparsePaths`); changelogs for the plugin and factory-parent, checked on every PR and release; `docs/ONBOARDING.md`; docs link check; java-pipeline 0.16.0 | ADR 0015, PR (this step) |

### Waiting on the owner
- Review and merge the #7 PR, then tag `java-pipeline-v0.16.0` (owner-approved).
- After 2.0.0 is published, Dependabot will open a parent-upgrade PR in payments-service that fails without
  the ADR 0010 code changes. Recommendation: close it, unless the owner wants payments-service upgraded.
- #1 needs a choice: GitHub Pro (about $4/month), public repos, or an organization.

### Next, in the owner's approved order
1. **#1 Repo guardrails.** Branch protection and secret scanning, once the plan choice above is made. Branch
   protection is what makes the #3 promotion-PR review mechanically required.

### After #7
Each new pipeline plugin gets its own plan for the owner's OK:
- A **frontend** pipeline, to complete the software.
- A **Python backend pipeline** for quant research.

Also planned: a standard intake step (idea → spec → owner approval).

## Working notes (this machine)
Moved to the troubleshooting section of [ONBOARDING.md](ONBOARDING.md#troubleshooting-this-machine-wsl--the-claude-code-sandbox).
