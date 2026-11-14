# Factory roadmap

Read this first in every new session. Then read `CLAUDE.md`, and for history, the ADRs in `docs/factory-adr/`
and `~/dev/factory/BOOTSTRAP-LOG.md`. Update this file in the same PR that finishes a step.

## Goal
Make claude-factory a production-ready software factory: agents take a spec through tests, implementation,
review and a PR, and the owner approves. The work is on the factory itself. `payments-service` exists only to
validate the factory: don't port factory changes to it or build features on it unless the owner asks.

**Done (ADR 0029, scope frozen 2026-11-14):** one real application of the owner's goes from a spec to running on a
cluster, built by the factory, and gets one week of unattended maintenance. What is left to get there: B6, B7 and
a minimal C1. Nothing else is added to the queue before that; the real application decides what comes after.

## How we work
- Run one session per step. Start the session with "Read docs/ROADMAP.md and continue", and end it when the step's PR merges.
- Plan before code. Write the step's plan to `docs/plans/<step>.md`, get the owner's OK, then implement. Delete
  the plan when the PR merges: the ADR and the PR description keep the reasoning. Steps in the autonomous queue
  below skip the wait: their plan is the PR description and the owner's merge is the approval.
- Send broad investigations to subagents so the main session stays small.
- In a session: merge, tag, push to `main`, create a repo, or change GitHub settings only after the owner says
  yes. Pushing a branch and opening a PR for a queued step needs no further yes (ADR 0017). Once B0's rulesets
  are in place, factory workflows may do more, within the limits of ADR 0020 (see `CLAUDE.md`).

## Autonomous queue (ADRs 0017, 0020)
The owner starts a session with "Read docs/ROADMAP.md and continue" (or just "go"). Take the first step below
that isn't done, bring it to a PR with green factory CI, and stop. One step per session, one PR per step. Tick
the step in the PR that finishes it. The steps come from the architecture audit of 2026-11-10 (java-pipeline
0.16.0): the factory is one strong production line, and these are what it lacks to work as a department.
B0–B7 come from the audit of 2026-11-12 (ADR 0020): they remove the reasons the owner has to step in (no
identity of its own, the laptop sandbox, a person at every gate). They come before C1 and the A steps. From B2 on, a step can also
run unattended: `gh workflow run factory-step.yml` (ADR 0022). Once B4 is done, merging a
step's PR starts the next step, and "go" is no longer needed.
C1 and the order A6, A4, A5 are the owner's decision of 2026-11-14: "deploy and maintain" can't be shown
without a cluster, and the evals come before the agents are reshaped.
A6, A4 and A5 are deferred by the scope freeze (ADR 0029). Their rows say "(deferred)", which also keeps the
chain from starting them: it only runs a row with a bare id.

| # | Step | Gap it closes | Done when |
|---|---|---|---|
| A1 ✅ | Autonomous-mode rules | Every action needed the owner's yes | Done: ADR 0017, PR #13 |
| A2 ✅ | Headless runner | The pipeline only ran in an interactive session on the owner's machine | Done: ADRs 0018, 0023; java-pipeline 0.19.2. Accepted 2026-11-13 on demo-service: issue #3 with `factory:build` ended in feature PR #6 (run 43324062313, agent ~5 min, verify green in the gate and in the PR's CI), with an architect review, a test per criterion, and a code review |
| A3 ✅ | Intake skill | Nothing turned an idea into a spec | Done: ADR 0019. Accepted 2026-11-13: issue #3 with `factory:spec` ended in spec PR #5 (run 43323066029), approved with the owner's answers and merged |
| B0 ✅ | Guardrails applied, ADR 0020 | The never-list was a rule the agent followed, not one GitHub enforced | Done: ADR 0020, PR #17; `protect-repo.sh` applied 2026-11-12 (rulesets `main` and `release tags`, secret scanning, CodeQL, Dependabot security updates); a PR with a red required check showed `BLOCKED` (PR #18, closed). Release tags can't be moved or deleted; who may create them is still open (see "Waiting on the owner") |
| B1 ✅ | Factory identity | The factory acted as the owner, and PRs opened with `GITHUB_TOKEN` didn't start CI | Done: ADR 0021, PR #19. App `nabiabdallah-factory-bot` (contents, pull requests, issues, workflows), installed on claude-factory; the identity check was green on 2026-11-12 (bot PR #20 started CI by itself) |
| B2 ✅ | Factory steps run in Actions | Factory work ran on the owner's laptop, in a sandbox that blocks `gh`, Maven Central, Docker and release assets | Done: ADR 0022, PR #21. The first unattended run (2026-11-12, ~7 min) took B2a and opened bot PR #22, which had green CI and was merged |
| B2a ✅ | Two-job service runner | The service runner (ADR 0018) gates and publishes from the checkout the agent could rewrite, so a rewritten `factory-run.sh` would pass its own gate and publish with the write token | `factory-feature.yml` in both templates split like ADR 0022: the agent job hands over a bundle and the report; the gate (including `./mvnw verify`) and publish run on a fresh checkout of the base. `ci/test-factory-run.sh` covers an agent that rewrites the runner. New java-pipeline minor release with an Upgrading note. Done: ADR 0023, java-pipeline 0.19.0 (four jobs: agent, gate, publish, report; the tag follows the merge, see "Waiting on the owner") |
| B3 ✅ | Service provisioning | Every service needed a repo, secrets, labels and protection set up by hand | Done: ADR 0024, PRs #23, #24. `new-service.yml` provisioned demo-service (run 43314997086), where the A2/A3 acceptance run passed. The first real runs found five shipped defects, all fixed: 0.19.1 (workflow GitHub rejected; factory-parent 2.1.1 with the zlib-fixed base; actionlint in CI, ADR 0025) and 0.19.2 (services let Actions open PRs; publish reports GitHub's reason) |
| B4 ✅ | Chaining and releases | Every hop waits for a person: "go", relabelling after a spec merges, tagging | Done: ADR 0026, PR #28, java-pipeline 0.20.0. `factory-chain.yml` starts the next step when a merge changes this file (and once a day); `release-tag.yml` tags a merged version bump with the App's token; in services, a merged `factory:spec` PR with `- Status: Approved` labels its issue and dispatches the build. Accepted 2026-11-13/14: merging #28 tagged 0.20.0 and started B5 (PR #29); on demo-service, merging spec PR #9 alone led to feature PR #10. One part failed there: CI dispatched by the runner doesn't count on its PRs. Fixed in 0.20.1 (ADR 0028): the runner opens PRs as the App, and `service-app.yml` gives an existing service the App |
| B5 (built, acceptance after the merge) | Risk tiers and auto-merge | The owner merges every PR, including mechanical ones | Built: ADR 0027. `risk-tier.yml` labels each PR `risk:low`/`risk:high` from its changed paths (`.github/scripts/risk-tier.sh`; unknown paths are high, `risk:high` is sticky). `auto-merge.yml` runs after CI on a PR: a low PR with green required checks and an independent read-only `code-reviewer` run saying APPROVE is merged by the App on the reviewed sha. `ci/test-risk-tier.sh` covers each path class and each refusal. Done when, on real PRs, a docs-only one merges by itself and a workflow one waits (merging B5 shows the second; the first needs a docs PR after it) |
| B6 (built, acceptance after the merge) | Usage brake and ledger | Nothing records what runs cost or stops dispatch when the subscription runs out | Built: ADR 0030. Each run's outcome, duration and usage are appended to `runs.jsonl` on the `factory-ledger` branch (new `ledger` job). A run that hits the usage limit ends as `usage-limit` (not a failure): nothing is published, and `resolve` and the chain refuse until the reset. `FACTORY_MAX_BUDGET_USD` stays as the runaway guard. `ci/test-factory-step.sh` simulates a limit. Done when the first real run after the merge shows in the ledger; the inbox line waits for B7 |
| B7 (built, acceptance after the merge) | Maintenance agent and decision inbox | Dependabot PRs, plugin drift and expiring exceptions wait until the owner notices; questions arrive one at a time | Built: ADR 0032. `factory-maintenance.yml` posts a weekly digest (runs and usage from the ledger, auto-merges, what is waiting, Dependabot triage with a recommendation each, `.trivyignore.yaml` expiries, the yearly token via variable `CLAUDE_TOKEN_EXPIRES`) to the pinned "Factory inbox" issue; an `inbox` job in `factory-step.yml` posts every stopped run there. `ci/test-factory-inbox.sh`. Not built: template-drift and plugin-upgrade PRs to services (needs the App's permissions, see ADR 0032). Done when the first digest posts and a stopped run shows up in the inbox |
| C1 | A real cluster | Deploy and the runtime half of maintenance are untested: no CD job, no post-deploy check, no alert-to-issue loop | Not unattended: it starts with a plan in `docs/plans/C1.md` and the owner's OK (where the cluster runs, who holds its credentials). The chain skips it (it only reads A and B ids), so A6 can run meanwhile. A small cluster (single-node k3s is enough) that demo-service deploys to. Done when a CD job rolls a merged promotion PR out to it and a post-deploy check reports the result. That unblocks the list under "Waiting for a real cluster" |
| A6 (deferred, ADR 0029) | Pipeline evals and metrics | CI tests scripts and templates, never agent behaviour; cost and cycle time aren't tracked | A benchmark spec runs through the pipeline on plugin changes and its result is recorded; each PR reports stages, attempts and reviewer findings. Comes before A4 and A5: once B5 auto-merges, agent behaviour has to be measured before the agents are restructured |
| A4 (deferred, ADR 0029) | Orchestrator and implementer split | The main session both conducts the stages and writes the code; a feature can't be resumed or split | An implementer agent; `new-feature` only orchestrates; per-feature state file so a new session resumes at the right stage |
| A5 (deferred, ADR 0029) | Domain rules out of the agents | Agents are hard-wired to banking (money, idempotency on transfers), which misfires on other software | Agents read a per-project profile; the banking checks become the `payments-example` profile; the skeleton gets a neutral one |

Not queued, and not before the definition of done above is met (each then needs its own plan and the owner's
OK): more roles (security reviewer, end-to-end tester),
a learning loop from reviewer findings back into
the agents, and the frontend and Python pipelines already listed under "After #1". GitOps, post-deploy checks
and the alert-to-issue loop wait for the cluster of step C1.

Where the work runs: a cloud session can't download Maven dependencies, so factory CI on the PR is the judge
there. Use the owner's machine for steps that change the templates or factory-parent.

## Status (2026-11-14)

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
- **Name the first real application** (ADR 0029): the one the factory has to take from a spec to a cluster. A
  Java backend can start now: the spec-to-PR path works (accepted on demo-service).
- **Merging B7's PR** adds the inbox and digest. Then: run `gh workflow run factory-maintenance.yml` once to see the digest, set the repository variable `CLAUDE_TOKEN_EXPIRES` (YYYY-MM-DD) to when the token's year ends, check that `factory-ledger` has a record for the B6 run, and decide whether template-drift PRs to services (left out of B7, ADR 0032) wait for the real application. C1 is next and needs your decisions (below).
- (done) Merging B6's PR started step B7 unattended.
- (done) Merging B5's PR started step B6 unattended (as B4 did for B5); `FACTORY_PAUSED=true` holds it, and from now
  also holds auto-merge. B5 acts on real PRs only after the merge: open a docs-only PR to see `risk:low` merge by
  itself. If the reviewer's `--allowedTools` flags don't behave on the pinned CLI, the first run fails (red, not
  merged); say so and a session fixes it.
- **Give demo-service the App (0.20.1, ADR 0028):** run
  `gh workflow run service-app.yml --repo nabiabdallah/claude-factory -f name=demo-service` (a session may not: it
  copies a secret). If the run warns that it could not add the repo to the App, add demo-service at the link it
  prints and run it again. demo-service PR #11 brings the 0.20.1 files; after both, the next runner PR there
  should go green with no click.
- **Who may create release tags:** today anyone with write access. Recommendation: a second tag ruleset that
  restricts creation to the factory App and repository admins, added to `ci/protect-repo.sh` and applied by you
  (a ruleset change is yours alone).
- demo-service PR #6 (the A2 acceptance feature) was merged on 2026-11-13 on your word. Its code review left 4
  points to decide before the next feature copies them: a repeated `name` parameter is joined as "a,b"; 400
  validation is hand-built in the controller (DomainException maps to 422); "characters" means code points;
  `GreetCommand` doesn't validate itself.
- Local leftovers: `~/dev/projects/demo-service` (0.18.0, never pushed) and `~/dev/projects/demo-service.stale-0.9.1`
  can be deleted, since B3 provisions the repo. Update the local plugin (`/plugin`), which is still at 0.9.1.
- Review payments-service PR #10 (spec 0005).
- After 2.0.0 is published, Dependabot will open a parent-upgrade PR in payments-service that fails without
  the ADR 0010 code changes. Recommendation: close it, unless the owner wants payments-service upgraded.
- #1 for payments-service (claude-factory is done, B0): with the owner's yes, make it public and run
  `ci/protect-repo.sh nabiabdallah/payments-service service`.
- Set the noreply commit email in both clones (`git config user.email
  99053318+nabiabdallah@users.noreply.github.com`); the sandbox can't write `.git/config`.
- **C1 (a real cluster) needs your decisions** before its plan: where the cluster runs (a single-node k3s on a
  small VM is the recommendation) and who holds its credentials. It comes after B7.

### Next, in the owner's approved order
1. **#1 Repo guardrails.** Decisions made 2026-11-08 (public repos incl. payments-service, existing history
   kept and noreply email from now on, no license, 0 required approvals, CodeQL on). `ci/protect-repo.sh`,
   `SECURITY.md` and ADR 0016 are in the step's PR; the step is done once the GitHub changes above are applied
   and checked. Branch protection is what makes the #3 promotion-PR review mechanically required.

### After #1
Each new pipeline plugin gets its own plan for the owner's OK:
- A **frontend** pipeline, to complete the software.
- A **Python backend pipeline** for quant research.

The intake step (idea → spec → owner approval) is queue step A3 above.

### Waiting for a real cluster
Step C1 in the queue provides the cluster. Follow-ups from ADRs 0009, 0012 and 0014 that need a cluster to
build or test:
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
