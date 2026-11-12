#!/usr/bin/env bash
# Workflow lint (factory ADR 0025): every workflow of the factory and the templates must load on GitHub. PyYAML
# accepts files GitHub rejects (an unquoted ": " in a name, the runner context in job-level env: 0.17.0-0.19.0
# shipped both), so this runs actionlint, pinned and checksum-verified, with its schema and expression checks.
# Shell and Python checks inside run steps are off for now; turning them on is its own change.
#   ci/lint-workflows.sh        (from the repo root; downloads actionlint unless ACTIONLINT is set)
set -euo pipefail

actionlint_version=1.7.12
actionlint_sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8

work="$(mktemp -d "${TMPDIR:-/tmp}/lint-workflows.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if [[ -z "${ACTIONLINT:-}" ]]; then
  curl -sSfL --connect-timeout 20 --retry 4 --retry-all-errors -o "$work/a.tgz" \
    "https://github.com/rhysd/actionlint/releases/download/v$actionlint_version/actionlint_${actionlint_version}_linux_amd64.tar.gz"
  echo "$actionlint_sha256  $work/a.tgz" | sha256sum -c --quiet -
  tar -xzf "$work/a.tgz" -C "$work" actionlint
  ACTIONLINT="$work/actionlint"
fi
lint() { "$ACTIONLINT" -no-color -shellcheck= -pyflakes= "$@"; }

# The check itself must catch the defect that shipped in 0.19.0.
cat > "$work/bad.yml" <<'YML'
on: push
jobs:
  j:
    runs-on: ubuntu-latest
    env:
      DIR: ${{ runner.temp }}/x
    steps:
      - run: echo "$DIR"
YML
if lint "$work/bad.yml" >/dev/null 2>&1; then
  echo "FAIL: actionlint accepts the runner context in job-level env; this check would not catch 0.19.0's defect"; exit 1
fi

mapfile -t files < <(find .github/workflows plugins/java-pipeline/templates/*/.github/workflows -name '*.yml' | sort)
if lint "${files[@]}"; then
  echo "workflow lint: OK (${#files[@]} workflows)"
else
  echo "workflow lint: the errors above would stop GitHub from loading these workflows"; exit 1
fi
