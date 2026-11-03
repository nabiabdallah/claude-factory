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
  for tool in cosign trivy; do
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

# 5. A built project has an SBOM that lists its real dependencies.
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
