#!/usr/bin/env bash
# Supply-chain checks for the factory and its templates (factory ADR 0009). Run from the repo root.
#   ci/check-supply-chain.sh            static checks (pins, workflow steps)
#   ci/check-supply-chain.sh <project>  also checks a built project: its SBOM (Spring Boot's, in the jar) lists its dependencies
set -euo pipefail

fail=0
problem() { echo "FAIL: $*"; fail=1; }

workflows=$(find .github/workflows plugins/java-pipeline/templates/*/.github/workflows -name '*.yml')

# 1. Every Action is pinned to a full commit SHA (tags can be moved; a SHA can't).
while IFS= read -r line; do
  problem "Action not pinned to a commit SHA: $line"
done < <(grep -HnE '^\s*-?\s*uses:' $workflows | grep -vE 'uses:\s*[^@[:space:]]+@[0-9a-f]{40}(\s+#\s*v[0-9][^[:space:]]*)?\s*$' || true)

# 2. The base image is pinned to a digest.
base=$(sed -n 's|.*<factory.image.base>\(.*\)</factory.image.base>.*|\1|p' parents/factory-parent/pom.xml)
[[ "$base" =~ @sha256:[0-9a-f]{64}$ ]] || problem "factory.image.base is not pinned to a digest: $base"

# 3. Downloaded tools are pinned by version and sha256.
for t in plugins/java-pipeline/templates/*; do
  tools="$t/.github/scripts/ci-tools.sh"
  [[ -f "$tools" ]] || { problem "$t: no .github/scripts/ci-tools.sh"; continue; }
  for tool in cosign trivy kubeconform; do
    grep -qE "^${tool}_sha256=[0-9a-f]{64}$" "$tools" || problem "$tools: $tool has no pinned sha256"
  done
done

# 4. Template CI scans the image on every run and signs + attests what it pushes.
for t in plugins/java-pipeline/templates/*; do
  ci="$t/.github/workflows/ci.yml"
  flat=$(tr -s '\n' ' ' < "$ci" | sed 's/\\ / /g') # folded/continued commands on one line
  grep -q 'jib:buildTar' <<<"$flat" || problem "$ci: no image tarball to scan"
  grep -qE 'trivy image .*--input' <<<"$flat" || problem "$ci: no Trivy scan of the image"
  grep -qE 'trivy .*--exit-code 1' <<<"$flat" || problem "$ci: Trivy scan does not fail the build"
  grep -qE 'cosign sign ' <<<"$flat" || problem "$ci: pushed image is not signed"
  grep -qE 'cosign attest .*cyclonedx' <<<"$flat" || problem "$ci: SBOM is not attested to the image"
  grep -qE 'id-token: write' <<<"$flat" || problem "$ci: keyless signing needs id-token: write"
done

# 5. The unattended feature run (factory ADR 0018): pinned CLI, no write token within the agent's reach, issue
#    text never on a command line, and both templates carry the same runner.
first=""
for t in plugins/java-pipeline/templates/*; do
  wf="$t/.github/workflows/factory-feature.yml"; runner="$t/.github/scripts/factory-run.sh"
  [[ -f "$wf" && -x "$runner" ]] || { problem "$t: no factory-feature.yml or executable factory-run.sh"; continue; }
  grep -qE '^claude_code_version=[0-9]+\.[0-9]+\.[0-9]+$' "$runner" || problem "$runner: Claude Code CLI is not pinned to an exact version"
  grep -qE '^\s+persist-credentials: false$' "$wf" || problem "$wf: checkout leaves GitHub credentials for the agent"
  ! grep -qE '^\s+run:.*\$\{\{' "$wf" || problem "$wf: a run command interpolates an expression (pass it through env)"
  agent_step=$(sed -n '/factory-run.sh agent/,/^      - name:/p' "$wf")
  ! grep -qE 'GH_TOKEN|GITHUB_TOKEN|github\.token|FACTORY_PR_TOKEN' <<<"$agent_step" || problem "$wf: the agent step is given a GitHub token"
  # ADR 0023: the agent job can't write, and what runs on the agent's tree is only ever a copy from the base.
  agent_job=$(sed -n '/^  agent:/,/^  gate:/p' "$wf")
  ! grep -qE '^\s+[a-z-]+: write\b' <<<"$agent_job" || problem "$wf: the agent job asks for a write permission"
  ! grep -qE 'factory-run\.sh (unpack|gate|publish)' "$wf" || problem "$wf: unpack, gate and publish must run the copy kept outside the checkout"
  # ADR 0026: the chain runs the default branch's runner, and CI can be dispatched for the runner's pull requests.
  grep -q 'factory-run.sh chain' "$t/.github/workflows/factory-chain.yml" 2>/dev/null || problem "$t: no factory-chain.yml that runs the chain phase"
  grep -qE '^  workflow_dispatch:' "$t/.github/workflows/ci.yml" || problem "$t: ci.yml can't be dispatched, so the runner's pull requests get no CI"
  if [[ -z "$first" ]]; then first="$t"; else
    cmp -s "$first/.github/scripts/factory-run.sh" "$runner" || problem "$runner differs from $first's"
    cmp -s "$first/.github/workflows/factory-feature.yml" "$wf" || problem "$wf differs from $first's"
    cmp -s "$first/.github/workflows/factory-chain.yml" "$t/.github/workflows/factory-chain.yml" || problem "$t's factory-chain.yml differs from $first's"
  fi
done

# 6. A built project has an SBOM that lists its real dependencies.
if [[ $# -gt 0 ]]; then
  bom="$1/target/classes/META-INF/sbom/application.cdx.json"
  if [[ ! -f "$bom" ]]; then
    problem "$bom missing"
  elif ! grep -q '"name" *: *"spring-core"' "$bom"; then
    problem "$bom does not list spring-core"
  fi
fi

[[ $fail -eq 0 ]] && echo "supply-chain checks: OK"
exit $fail
