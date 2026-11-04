# 0012. Deploy safety: overlays, promotion gate, migration rollout rule, PDB, NetworkPolicy

- Status: Accepted
- Date: 2026-11-04
- Deciders: Noel Abi Abdallah

## Context
ADR 0007 gave every service one Kustomize base with `newTag: main`: applying it deployed whatever was last
pushed to `main`, and nothing gated that. The rollout was always `RollingUpdate`, so a migration the previous
version can't run against (payments-service spec 0005, V3) needed a hand-made `kubectl patch` to `Recreate`.
There was no PodDisruptionBudget (a node drain could take both replicas), no NetworkPolicy and no
environments. There is still no cluster, so the gate has to live in git and CI.

## Decision
- **Layout** (both templates): `deploy/k8s/base` (Deployment, Service, PDB, NetworkPolicy; no image tag),
  `overlays/staging` (namespace `<service>-staging`, 1 replica) and `overlays/prod` (`<service>-prod`,
  3 replicas), and a Kustomize Component `components/recreate` that sets `strategy: Recreate`.
  Overlays start at `newTag: unreleased`, a tag that never exists, so applying before the first promotion fails
  at image pull instead of running something unreviewed.
- **Promotion gate:** deploying is a PR that changes an overlay's `newTag`; the owner's review of it is the gate.
  `.github/scripts/check-deploy.sh` runs in a new `manifests` CI job (full history) and fails when an overlay
  doesn't render or match the schemas (kubeconform `-strict`, Kubernetes 1.31; kubeconform v0.8.0 pinned by
  sha256 in `ci-tools.sh`), when an image tag isn't a 40-hex commit on `main` (or `unreleased`): `main`,
  `latest`, no tag, a branch commit or an unknown commit are all rejected.
  Digests are not accepted: a digest can't be traced to a commit, which the migration rule needs.
- **Migration rollout rule:** `add-postgres` adds `MigrationRolloutTest` (runs in `verify`). A migration with a
  statement the previous version may not survive (drop of a table/column/view/type/function/sequence, rename,
  column type change, `SET NOT NULL`, NOT NULL column without default, new constraint or unique index) must
  start with `-- rollout: compatible — <why>` or `-- rollout: recreate — <why>`. On a promotion,
  `check-deploy.sh` looks at the migrations added between the old and new tag: if one says `recreate`, the
  overlay must include `components/recreate`; if none does, it must not, so the component never outlives its
  release and rolling update stays the default. It also rejects promotions that change a released migration
  and rollbacks that cross a migration (roll forward instead). The first promotion of an environment
  (from `unreleased`) is exempt: nothing is running.
- **PodDisruptionBudget:** `maxUnavailable: 1`, not `minAvailable: 1`, which would block every node drain in a
  1-replica environment. It limits evictions only; rollouts are governed by the strategy.
- **NetworkPolicy:** default deny both ways. In: the `http` port from namespaces labelled
  `claude-factory/ingress=true`. Out: DNS to `kube-system`, TCP 443 (identity provider) and 5432 (Postgres) to
  any address. Enforced only by network plugins that support NetworkPolicy.
- **Pipeline:** the spec template gains a Rollout section; architect-reviewer blocks on an unstated rollout
  for schema/API changes; code-reviewer checks that rollout headers are true.
- **Factory CI:** renders and validates every overlay of both templates, plus prod with `components/recreate`;
  `ci/test-check-deploy.sh` runs the gate on a generated project with Postgres through 15 cases (mutable tags,
  untagged image, branch and unknown commits, first promotion, recreate needed/present/left behind, unchanged
  tag, rollback, compatible migration, edited migration).

## Alternatives considered
- **CD from Actions or GitOps (Argo CD/Flux) now** — needs a cluster; the overlay-tag-in-git model is what both
  would consume later.
- **GitHub Environments with required reviewers** — the natural gate, but needs a paid plan for private repos
  (step #1's choice). The promotion PR works today and becomes mechanically required with branch protection.
- **Warn instead of fail when `components/recreate` is left in** — owner chose fail: a forgotten Recreate means
  needless downtime on every later release.
- **Detect breaking migrations only by review** — the test makes it a build failure that an agent can't miss;
  reviewers still judge whether "compatible" is true.

## Consequences
- Positive: nothing reaches a cluster without a reviewed commit pin; breaking migrations are declared in the
  migration itself and their rollout is checked mechanically; drains and lateral traffic are bounded.
- Negative: the migration check is a pattern match, not a SQL parser; unusual statements can slip through, and
  some safe ones (a unique index on a new table) need a "compatible" header.
- Negative: an image tag being on `main` doesn't prove its image job succeeded; the cluster will fail the pull.
- Negative: egress 443/5432 is open to any address until real CIDRs exist.
- Follow-ups: cluster admission that verifies the cosign signature (policy-controller/Kyverno), a CD job,
  Environments and branch protection (#1), Ingress/Gateway, egress CIDRs, HPA.
- Amends ADR 0007's deploy-manifest section (single base, `newTag: main`).
