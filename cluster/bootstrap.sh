#!/usr/bin/env bash
# Turns a fresh Ubuntu arm64 VM into the factory's cluster (factory ADR 0034): single-node k3s, Flux, and one Flux
# source on this repository's cluster/flux, which registers the services. cluster/cloud-init.yaml runs it at first
# boot; docs/CLUSTER.md is the runbook. Run it again as root to repair or, after the pins below changed, to upgrade:
#   curl -sSfL https://raw.githubusercontent.com/nabiabdallah/claude-factory/main/cluster/bootstrap.sh | sudo bash
# Nothing here holds or asks for a credential: the repositories and images are public, and the one secret (the
# token Flux reports commit statuses with) is created by the owner on the VM.
#   bootstrap.sh                    do everything
#   bootstrap.sh firewall-rules F   print iptables rules file F with the cluster's rules added (what CI tests)
set -euo pipefail

# Pinned by version and sha256 (factory ADR 0009). Bump a version together with its checksums: the sha256 is the
# "digest" of the release asset in the GitHub API; install.sh is the file at the release tag.
k3s_version='v1.36.6+k3s1'
k3s_arm64_sha256=49dcecdb4f64f5e92bdc52d204d407fb39729e492f09074488125ee58b6f2895
k3s_install_sha256=46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad
flux_version=v2.10.0
flux_install_sha256=a8c838ccd9be5d30eba9df87cd229b7c4eb80c0049fba1bc3b9840829f267f28

factory_raw=https://raw.githubusercontent.com/nabiabdallah/claude-factory/main
pod_cidr=10.42.0.0/16 # k3s' default
marker='claude-factory k3s'

say() { echo "bootstrap: $*"; }
die() { echo "bootstrap: $*" >&2; exit 1; }
fetch() { # url sha256 output
  curl -sSfL --connect-timeout 20 --retry 5 --retry-all-errors -o "$3" "$1"
  echo "$2  $3" | sha256sum -c --quiet - || die "checksum mismatch for $1"
}

# Oracle's Ubuntu image ends its INPUT and FORWARD chains with a REJECT, which cuts pods off from the node (the
# API server, DNS) and from each other. Let the pod network through, before those rules. What reaches the VM from
# outside is decided by the Oracle security list, which stays at SSH only.
firewall_rules() { # <rules file> -> the file with the cluster's rules, once
  if grep -q -- "$marker" "$1"; then cat "$1"; return; fi
  awk -v cidr="$pod_cidr" -v m="$marker" '
    /^-A INPUT (.* )?-j REJECT/ && !i { print "-A INPUT -s " cidr " -m comment --comment \"" m "\" -j ACCEPT"; i = 1 }
    /^-A FORWARD (.* )?-j REJECT/ && !f {
      print "-A FORWARD -s " cidr " -m comment --comment \"" m "\" -j ACCEPT"
      print "-A FORWARD -d " cidr " -m comment --comment \"" m "\" -j ACCEPT"; f = 1 }
    { print }' "$1"
}

if [[ "${1:-}" == firewall-rules ]]; then
  [[ -f "${2:-}" ]] || die "usage: bootstrap.sh firewall-rules <rules file>"
  firewall_rules "$2"; exit 0
fi
[[ $# -eq 0 ]] || die "usage: bootstrap.sh [firewall-rules <rules file>]"
[[ $EUID -eq 0 ]] || die "run it as root"
[[ "$(uname -m)" == aarch64 ]] || die "this script pins the arm64 build of k3s; this machine is $(uname -m)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
kubectl() { /usr/local/bin/k3s kubectl "$@"; }

rules=/etc/iptables/rules.v4
if [[ -f "$rules" ]] && ! grep -q -- "$marker" "$rules"; then
  say "opening the host firewall for the pod network"
  firewall_rules "$rules" > "$work/rules.v4"
  iptables-restore --test "$work/rules.v4" || die "the new firewall rules do not load; $rules is unchanged"
  cp "$rules" "$rules.before-claude-factory"
  install -m 644 "$work/rules.v4" "$rules"
  iptables-restore "$rules"
fi

if /usr/local/bin/k3s --version 2>/dev/null | grep -qF "$k3s_version"; then
  say "k3s $k3s_version is installed"
else
  say "installing k3s $k3s_version"
  fetch "https://github.com/k3s-io/k3s/releases/download/${k3s_version/+/%2B}/k3s-arm64" "$k3s_arm64_sha256" "$work/k3s"
  fetch "https://raw.githubusercontent.com/k3s-io/k3s/${k3s_version/+/%2B}/install.sh" "$k3s_install_sha256" "$work/install.sh"
  install -m 755 "$work/k3s" /usr/local/bin/k3s
  # No ingress controller and no service load balancer: nothing is published yet (ADR 0034). The API server
  # listens on 6443, which the Oracle security list does not open. Secrets are encrypted at rest.
  INSTALL_K3S_SKIP_DOWNLOAD=true \
    INSTALL_K3S_EXEC="server --disable=traefik --disable=servicelb --secrets-encryption --write-kubeconfig-mode=600" \
    sh "$work/install.sh"
fi
say "waiting for the node"
for _ in $(seq 60); do kubectl get nodes >/dev/null 2>&1 && break; sleep 5; done
kubectl wait --for=condition=Ready node --all --timeout=300s

say "installing Flux $flux_version"
fetch "https://github.com/fluxcd/flux2/releases/download/$flux_version/install.yaml" "$flux_install_sha256" "$work/flux.yaml"
kubectl apply --server-side --force-conflicts -f "$work/flux.yaml" >/dev/null
kubectl -n flux-system wait --for=condition=Available deployment --all --timeout=300s

say "pointing Flux at claude-factory's cluster/flux"
curl -sSfL --connect-timeout 20 --retry 5 --retry-all-errors -o "$work/sync.yaml" "$factory_raw/cluster/flux/sync.yaml"
kubectl apply -f "$work/sync.yaml"

say "done. Flux now applies cluster/flux of claude-factory and each registered service's overlays."
say "Left for the owner (docs/CLUSTER.md): the secret 'github-status' in flux-system, so rollouts are reported."
