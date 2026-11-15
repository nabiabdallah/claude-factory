#!/usr/bin/env bash
# Checks cluster/ (factory ADR 0034): the bootstrap script's pins and firewall edit, the cloud-init file, and the
# Flux manifests: every service is confined to its own namespaces, reports its rollouts, and the files match
# the schemas of Kubernetes and of the pinned Flux release. No cluster.
#   ci/check-cluster.sh        (from the repo root)
# The schema check needs kubectl and kubeconform on PATH (CI has both) and downloads Flux's CRD schemas, unless
# FLUX_SCHEMAS names a directory that holds them; without the tools it is skipped with a warning, and fails in CI.
set -euo pipefail

flux_schemas_sha256=a1d64309d0965ef681f161ce2d28a1a58aa78239d6f5e94ea6e556b5674cfefb # crd-schemas.tar.gz of flux_version

fail=0
problem() { echo "FAIL: $*"; fail=1; }
ok() { echo "ok   - $1"; }
b=cluster/bootstrap.sh
work="$(mktemp -d "${TMPDIR:-/tmp}/check-cluster.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# 1. The script loads, and everything it downloads and runs is pinned.
[[ -x "$b" ]] && bash -n "$b" && ok "bootstrap.sh is executable and parses" || problem "$b is not executable or does not parse"
for pin in k3s_arm64_sha256 k3s_install_sha256 flux_install_sha256; do
  grep -qE "^$pin=[0-9a-f]{64}$" "$b" || problem "$b: $pin is not a sha256"
done
grep -qE "^k3s_version='v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+'$" "$b" && grep -qE '^flux_version=v[0-9]+\.[0-9]+\.[0-9]+$' "$b" \
  && ok "k3s and Flux are pinned to exact versions with checksums" || problem "$b: k3s or Flux is not pinned to an exact version"
# Every download but the factory's own sync.yaml goes through fetch (which checks the sha256).
[[ "$(grep -cE '^\s*curl ' "$b")" == 2 ]] && grep -qE '^\s*curl .*"\$factory_raw/cluster/flux/sync\.yaml"$' "$b" \
  && ok "only this repository's sync.yaml is downloaded without a checksum" || problem "$b: a download bypasses fetch"
! grep -qiE 'token|password|secret=' <(grep -vE '^\s*#|secrets-encryption|github-status' "$b") \
  && ok "the script handles no credential" || problem "$b mentions a credential"
flux_version="$(sed -n 's/^flux_version=//p' "$b")"

# 2. The firewall edit: Oracle's rules get the pod network before each REJECT, once.
cat > "$work/rules.v4" <<'RULES'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
-A OUTPUT -d 169.254.0.0/16 -j InstanceServices
COMMIT
RULES
"$b" firewall-rules "$work/rules.v4" > "$work/new.v4"
want='-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -s 10.42.0.0/16 -m comment --comment "claude-factory k3s" -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -s 10.42.0.0/16 -m comment --comment "claude-factory k3s" -j ACCEPT
-A FORWARD -d 10.42.0.0/16 -m comment --comment "claude-factory k3s" -j ACCEPT
-A FORWARD -j REJECT --reject-with icmp-host-prohibited'
[[ "$(sed -n '6,11p' "$work/new.v4")" == "$want" && "$(wc -l < "$work/new.v4")" == 13 ]] \
  && ok "firewall: the pod network is accepted before each REJECT, nothing else changes" || problem "firewall rules are not what was expected: $(cat "$work/new.v4")"
"$b" firewall-rules "$work/new.v4" | cmp -s - "$work/new.v4" && ok "firewall: a second run changes nothing" || problem "firewall edit is not idempotent"
! grep -qE -- '--dport|0\.0\.0\.0/0' <(diff "$work/rules.v4" "$work/new.v4" | grep '^>') && ok "firewall: no port is opened to the outside" || problem "the firewall edit opens a port"

# 3. cloud-init runs that script from this repository's main branch, and nothing else.
python3 - <<'PY' && ok "cloud-init.yaml is a cloud-config that runs cluster/bootstrap.sh from main" || problem "cluster/cloud-init.yaml is not what the runbook describes"
import sys, yaml
text = open("cluster/cloud-init.yaml").read()
doc = yaml.safe_load(text)
cmds = doc.get("runcmd", [])
good = (text.startswith("#cloud-config\n") and set(doc) <= {"package_update", "packages", "runcmd"} and len(cmds) == 1
        and "https://raw.githubusercontent.com/nabiabdallah/claude-factory/main/cluster/bootstrap.sh" in cmds[0][-1]
        and cmds[0][-1].count("http") == 1)
sys.exit(0 if good else 1)
PY

# 4. The Flux manifests: what a service may touch, and that its rollouts are reported.
python3 - <<'PY' || fail=1
import glob, os, sys, yaml
bad = []
listed = set(yaml.safe_load(open("cluster/flux/kustomization.yaml"))["resources"])
files = {os.path.basename(f) for f in glob.glob("cluster/flux/*.yaml")} - {"kustomization.yaml"}
if listed != files: bad.append(f"kustomization.yaml lists {sorted(listed)}, the directory holds {sorted(files)}")
objs = [o for f in sorted(files) for o in yaml.safe_load_all(open(f"cluster/flux/{f}")) if o]
def of(kind): return [o for o in objs if o["kind"] == kind]
names = lambda kind: {o["metadata"]["name"] for o in of(kind)}
namespaces, repos = names("Namespace"), {o["metadata"]["name"]: o for o in of("GitRepository")}
bindings = {(o["metadata"]["namespace"], s["name"]) for o in of("RoleBinding") for s in o["subjects"]
            if s["kind"] == "ServiceAccount" and s.get("namespace") == "flux-system"}
alerted = {s["name"] for o in of("Alert") for s in o["spec"]["eventSources"] if s["kind"] == "Kustomization"}
for o in of("ClusterRoleBinding") + of("ClusterRole"): bad.append(f"{o['kind']} {o['metadata']['name']}: nothing here may grant cluster-wide rights")
for o in of("RoleBinding"):
    if o["metadata"]["namespace"] not in namespaces or o["metadata"]["namespace"] in ("flux-system", "kube-system", "default"):
        bad.append(f"RoleBinding in {o['metadata']['namespace']}: only a service's own namespaces")
for o in of("Namespace"):
    if o["metadata"].get("labels", {}).get("pod-security.kubernetes.io/enforce") != "restricted":
        bad.append(f"Namespace {o['metadata']['name']}: pods are not held to the restricted standard")
for o in of("GitRepository"):
    if not o["spec"]["url"].startswith("https://github.com/nabiabdallah/") or o["spec"]["ref"] != {"branch": "main"}:
        bad.append(f"GitRepository {o['metadata']['name']}: not the main branch of one of the owner's repositories")
    if "secretRef" in o["spec"]: bad.append(f"GitRepository {o['metadata']['name']}: the cluster holds no GitHub read credential")
services = 0
for o in of("Kustomization"):
    if o["apiVersion"].startswith("kustomize.config"): continue
    n, s = o["metadata"]["name"], o["spec"]
    if n == "cluster":
        if s["path"] != "./cluster/flux" or s["sourceRef"]["name"] != "claude-factory": bad.append("the cluster Kustomization must apply ./cluster/flux of claude-factory")
        continue
    services += 1
    ns, sa = s.get("targetNamespace"), s.get("serviceAccountName")
    if not sa: bad.append(f"{n}: no serviceAccountName (it would run with Flux's cluster-wide rights)")
    if ns not in namespaces: bad.append(f"{n}: targetNamespace {ns} is not a namespace declared here")
    if (ns, sa) not in bindings: bad.append(f"{n}: {sa} has no RoleBinding in {ns}")
    if not (s.get("wait") is True and s.get("timeout") and s.get("prune") is True): bad.append(f"{n}: wait, timeout and prune must be set (the post-deploy check)")
    if not s["path"].startswith("./deploy/k8s/overlays/"): bad.append(f"{n}: path is not an overlay")
    if s["sourceRef"]["name"] not in repos or s["sourceRef"]["name"] == "claude-factory": bad.append(f"{n}: source is not a service repository declared here")
    if n not in alerted: bad.append(f"{n}: no Alert reports its rollouts")
for o in of("Provider"):
    s = o["spec"]
    if s["type"] != "github" or s.get("secretRef") != {"name": "github-status"} or s.get("commitStatusExpr") != "'flux/' + event.involvedObject.name":
        bad.append(f"Provider {o['metadata']['name']}: must post flux/<name> to GitHub with the github-status secret")
if any(o["kind"] == "Secret" for o in objs): bad.append("a Secret is committed")
if not services: bad.append("no service is registered")
for b in bad: print("FAIL:", b)
if not bad: print(f"ok   - {services} service environment(s): confined to their namespaces, rollouts reported")
sys.exit(1 if bad else 0)
PY

# 5. The schemas: Kubernetes' own and the pinned Flux release's.
if command -v kubectl >/dev/null && command -v kubeconform >/dev/null; then
  schemas="${FLUX_SCHEMAS:-}"
  if [[ -z "$schemas" ]]; then
    schemas="$work/flux"; mkdir -p "$schemas"
    curl -sSfL --connect-timeout 20 --retry 4 --retry-all-errors -o "$work/crd.tgz" \
      "https://github.com/fluxcd/flux2/releases/download/$flux_version/crd-schemas.tar.gz"
    echo "$flux_schemas_sha256  $work/crd.tgz" | sha256sum -c --quiet -
    tar -xzf "$work/crd.tgz" -C "$schemas"
  fi
  kubectl kustomize cluster/flux > "$work/rendered.yaml"
  kubeconform -strict -summary -kubernetes-version 1.31.0 -schema-location default \
    -schema-location "$schemas/{{.ResourceKind}}{{.KindSuffix}}.json" - < "$work/rendered.yaml" \
    && ok "cluster/flux renders and matches the schemas (Flux $flux_version)" || problem "cluster/flux does not match the schemas"
elif [[ -n "${CI:-}" ]]; then
  problem "kubectl and kubeconform are needed in CI"
else
  echo "skip - schema check (no kubectl or kubeconform here; CI runs it)"
fi

[[ $fail -eq 0 ]] && echo "cluster checks: OK"
exit $fail
