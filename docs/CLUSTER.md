# The cluster: runbook

One ARM VM on Oracle Cloud Always Free, single-node k3s, Flux pulling from git
([ADR 0034](factory-adr/0034-pull-based-deploys.md)). GitHub holds no cluster credentials, and the cluster's API is
not reachable from the internet: you look at it over SSH. Everything the cluster runs is described in
[`cluster/`](../cluster) of this repository.

| File | What it is |
|---|---|
| `cluster/cloud-init.yaml` | Pasted once when the VM is created. Downloads and runs `bootstrap.sh`. |
| `cluster/bootstrap.sh` | Installs k3s and Flux (pinned by version and sha256) and points Flux at `cluster/flux`. Safe to run again. |
| `cluster/flux/sync.yaml` | Flux's source on this repository. |
| `cluster/flux/<service>.yaml` | One per service: its namespaces, what Flux may do there, where its overlays are, where rollouts are reported. |

## 1. Create the VM (once, about 10 minutes)

Before you start, promote staging and prod of each registered service once (`gh workflow run promote.yml -f
env=staging`, then `prod`, in the service's repository, and merge the pull requests). An environment still at
`unreleased` has no image to pull: the cluster reports it as a failed rollout and the service gets a "Deploy
failed" issue.

In the Oracle Cloud console, in your home region: **Compute → Instances → Create instance**.
- **Image:** Canonical Ubuntu 24.04 (the aarch64 build; it is chosen with the shape).
- **Shape:** Ampere, `VM.Standard.A1.Flex`, 4 OCPUs, 24 GB. That is the whole Always Free allowance.
- **Networking:** the default virtual cloud network and a public IPv4 address. Leave the security list as it is:
  it lets in SSH (22) and nothing else.
- **SSH keys:** upload your public key.
- **Boot volume:** 100 GB (up to 200 GB is free).
- **Advanced options → Management → Cloud-init script:** paste the content of
  [`cluster/cloud-init.yaml`](../cluster/cloud-init.yaml).

If the console says "Out of host capacity", try again later or in another availability domain; upgrading the
account to Pay As You Go (still free within the allowance) usually ends it, and stops Oracle reclaiming an idle VM.

**Check** (about five minutes after it starts):
```bash
ssh ubuntu@<public ip>
sudo tail -n 3 /var/log/claude-factory-bootstrap.log    # ends with "bootstrap: done. ..."
sudo k3s kubectl get nodes                              # Ready
sudo k3s kubectl -n flux-system get kustomizations      # cluster, <service>-staging, <service>-prod: Ready True
```

## 2. Let Flux report rollouts (once, and again when the token expires)

1. GitHub → Settings → Developer settings → **Fine-grained tokens** → Generate new token. Repository access: only
   the service repositories (today `market-rates`). Repository permissions: **Commit statuses: Read and write**,
   nothing else. Expiry: one year at most.
2. On the VM (the token is read from the keyboard, so it stays out of the shell history):
   ```bash
   read -rs TOKEN && sudo k3s kubectl -n flux-system create secret generic github-status \
     --from-literal=token="$TOKEN" --dry-run=client -o yaml | sudo k3s kubectl apply -f - ; unset TOKEN
   ```

**Check:** `sudo k3s kubectl -n flux-system get providers,alerts` shows them Ready, and the next commit on the
service's `main` gets the statuses `flux/<service>-staging` and `flux/<service>-prod`.

Until the secret exists, or after the token expires, rollouts still happen and nothing is reported. The same two
steps replace an expired token. Add a repository to the token when a service is registered.

## 3. Deploy and roll back

Deploying is merging a promotion pull request in the service's repository
([ONBOARDING.md §8](ONBOARDING.md#8-deploy)): `gh workflow run promote.yml -f env=staging` opens it. Flux
notices within about a minute, waits up to five minutes for the new pods to be ready, and posts the status on
the merge commit.

- **Green:** the new version runs.
- **Red:** the previous version keeps serving, and the service gets the issue "Deploy failed: flux/<service>-<env>".
  Fix forward with a new promotion, or roll back: `gh workflow run promote.yml -f env=<env> -f commit=<the
  commit that ran before>` (or revert the promotion pull request). The issue closes itself on the next green
  status. `check-deploy.sh` refuses a rollback that crosses a database migration.

## 4. Look at it

```bash
ssh ubuntu@<public ip>
sudo k3s kubectl -n market-rates-staging get pods
sudo k3s kubectl -n market-rates-staging logs deploy/market-rates
sudo k3s kubectl -n flux-system get kustomizations                    # what is applied, at which commit
sudo k3s kubectl -n flux-system describe kustomization market-rates-staging   # why a rollout failed
```
Call a service from your machine (nothing is published to the internet yet):
```bash
ssh -L 8080:localhost:8080 ubuntu@<public ip> sudo k3s kubectl -n market-rates-prod port-forward svc/market-rates 8080:80
curl localhost:8080/...
```

## 5. Register a service

A pull request in this repository (it is `risk:high`: you merge it):
1. Copy `cluster/flux/market-rates.yaml` to `cluster/flux/<service>.yaml` and replace the name throughout.
2. Add the file to `cluster/flux/kustomization.yaml`.
3. `ci/check-cluster.sh` (in CI's `manifests` job) checks that the service is confined to its own namespaces and
   reports its rollouts.

After the merge Flux creates the namespaces within ten minutes. Add the repository to the status token (§2). A
service with a database needs its Secret created in each namespace by you (the template's README says which).

## 6. Upgrade k3s or Flux

Not automatic. Change the version and its checksums in `cluster/bootstrap.sh` (the header says where they come
from; for Flux also `flux_schemas_sha256` in `ci/check-cluster.sh`), merge, then on the VM:
```bash
curl -sSfL https://raw.githubusercontent.com/nabiabdallah/claude-factory/main/cluster/bootstrap.sh | sudo bash
```
k3s restarts: a short outage on one node. Ubuntu installs its own security updates (unattended-upgrades).

## 7. Rebuild from nothing

The VM holds no state that isn't in git, except the `github-status` secret. Terminate it, do §1 and §2 again.
A service with a database is the exception, once one exists: its data and Secret must be restored by hand.

## Troubleshooting

- **The bootstrap log stops at "waiting for the node", or pods can't resolve names.** Oracle's Ubuntu image
  rejects traffic it doesn't know; the script adds the pod network to `/etc/iptables/rules.v4` (the original is
  kept as `rules.v4.before-claude-factory`). Check `sudo iptables -S INPUT | grep claude-factory`; if the rule is
  missing, the image's rules file changed shape: run the script again and read its output.
- **`providers` is not Ready.** The `github-status` secret is missing (§2), or Flux rejects the status name's
  expression: `sudo k3s kubectl -n flux-system describe provider <service>-status` says which.
- **A Kustomization says "forbidden".** The service's manifests touch something outside its namespaces. That is
  the confinement working; the change belongs in `cluster/flux` instead, reviewed here.
- **Pods are rejected by "PodSecurity".** The namespaces enforce the restricted standard; the templates'
  Deployment meets it. A service that changed its `securityContext` has to restore it.
- **No statuses on commits.** The token expired or doesn't cover the repository (§2).
