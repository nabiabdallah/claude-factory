# 0034. The cluster pulls deploys; a commit status is the post-deploy check

- Status: Accepted
- Date: 2026-11-15
- Deciders: Noel Abi Abdallah
- Builds on: [ADR 0012](0012-deploy-safety.md) (promotion is a pull request),
  [ADR 0029](0029-scope-freeze-and-definition-of-done.md) (C1's cluster)

## Context
Roadmap step C1 gives the factory its first cluster: one ARM VM on Oracle Cloud Always Free, single-node k3s
(ADR 0029, amended 2026-11-15). Until now a promotion pull request changed a tag in git and nothing carried it
further: no CD job, no check after a deploy, no way for a failed rollout to reach the owner. The service images
were built for amd64 only, which an ARM node can't run. market-rates, the first real application, has no
database, no login and no secrets, and it, its image and claude-factory are public.

## Decision
The owner approved these on 2026-11-15 (`docs/plans/C1.md`, all seven recommendations).
- **The cluster pulls.** Flux runs in the cluster and applies each environment's overlay from the service's
  default branch. Merging the promotion pull request is the deploy. GitHub holds no cluster credentials, and
  the cluster's API is not opened to the internet.
- **The rollout's result is a commit status.** Flux waits for the new pods to be ready and posts
  `flux/<service>-<env>` on the commit it applied. The token it uses can set commit statuses on the service
  repositories and nothing else; the owner creates it and stores it in the cluster.
- **A failed rollout becomes an issue.** `post-deploy.yml` in the service turns a red status into the issue
  "Deploy failed: <context>" (label `deploy-failed`): one per environment, one comment per further failing
  commit, closed by the next green status. The status' text is treated as text from outside.
- **Promotions are opened by a workflow a person starts.** `promote.yml` picks the newest commit on the default
  branch whose image exists for every platform (or takes a named commit), and opens the pull request as the
  factory's App. `check-deploy.sh` judges it like a hand-made one, and deploy files stay `risk:high`: a person
  merges every promotion.
- **Images are built for `linux/amd64` and `linux/arm64`** under one tag, by a flag in the service's CI (no
  factory-parent release). cosign signs the index and both images; Trivy scans both.
- **Staging and prod are two namespaces on the one VM**, with the overlays as they are.
- **The cluster's own configuration lives in `cluster/` of claude-factory** (second half of C1): the VM's
  cloud-init, and one file per service that registers it with Flux under a service account limited to that
  service's namespaces. The owner creates the VM from it in the Oracle console.
- **No public ingress yet.** market-rates is reached over an SSH port-forward.

## Alternatives considered
- **A CD job in Actions that runs `kubectl apply`:** GitHub would hold a credential that can change the cluster,
  and the cluster's API would have to be reachable from GitHub's runners.
- **A workflow that polls a public URL of the service for the new version:** needs ingress, TLS and a version
  endpoint, all of which are deferred.
- **Open a promotion pull request after every merge to `main`:** most merges are docs or dependency bumps; a pull
  request each is noise while a person merges them all.
- **Terraform for the VM, run by a session:** an Oracle credential in a session, for a VM that is created once.
- **A separate repository for the cluster's configuration:** one more repository to protect, for one cluster.

## Consequences
- Positive: a merged promotion rolls out and reports back with no cluster credential outside the cluster.
- Positive: the "Deploy failed" issue is the first piece of the alert-to-issue loop, in a place the weekly digest
  can count.
- Negative: Flux polls, so a rollout starts up to about a minute after the merge.
- Negative: the status token expires (a year at most). Rollouts still happen after that, but report nothing,
  until it is replaced.
- Negative: one node. A reboot is an outage; three prod replicas give rolling updates, not availability.
- Negative: images pushed before java-pipeline 0.22.0 are amd64 only and can't be promoted to this cluster.
- Still open, on the roadmap's cluster list: admission check of the cosign signature, GitHub Environments,
  ingress, narrowed egress, HPA, the OpenTelemetry Collector, dashboards and alerts, automatic promotion,
  registering a service from `new-service.yml`, and k3s and Flux upgrades.
