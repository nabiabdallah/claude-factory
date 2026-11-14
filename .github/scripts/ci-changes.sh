#!/usr/bin/env bash
# Factory CI's two decisions (factory ADR 0031), kept out of the workflow so ci/test-ci-changes.sh can test them:
#   scope     paths on stdin, one per line -> "docs" when every path is under docs/ or is a Markdown file in the
#             repo root, else "full". No paths, or anything unexpected, is "full": the build jobs run.
#   verdict   the required check "Template builds and new-project works": SCOPE (full|docs) and RESULTS, lines of
#             "<job> <result>" for every job it waits for. `changes` and `scripts` must have succeeded. A build job
#             must have succeeded, or been skipped when the scope is docs.
set -euo pipefail

build_jobs="templates new-project postgres resource-server build-rules"

case "${1:-}" in
  scope)
    seen=0 scope=docs
    while IFS= read -r path || [[ -n "$path" ]]; do
      [[ -n "$path" ]] || continue
      seen=1
      [[ "$path" =~ ^docs/.+ || "$path" =~ ^[^/]+\.md$ ]] || scope=full
    done
    [[ $seen -eq 1 ]] || scope=full
    echo "$scope"
    ;;

  verdict)
    scope="${SCOPE:-}"
    [[ "$scope" == full || "$scope" == docs ]] || { echo "ci: no usable scope ('$scope'): the changes job did not finish" >&2; exit 1; }
    result_of() { awk -v j="$1" '$1 == j { print $2; found = 1 } END { if (!found) print "missing" }' <<<"${RESULTS:-}"; }
    fails=0
    for job in changes scripts; do
      r="$(result_of "$job")"
      [[ "$r" == success ]] || { echo "ci: $job: $r" >&2; fails=1; }
    done
    for job in $build_jobs; do
      r="$(result_of "$job")"
      if [[ "$r" == success ]] || [[ "$r" == skipped && "$scope" == docs ]]; then continue; fi
      echo "ci: $job: $r (scope $scope)" >&2; fails=1
    done
    [[ $fails -eq 0 ]] || exit 1
    [[ "$scope" == docs ]] && echo "ci: docs-only change, the build jobs were skipped" || echo "ci: all jobs passed"
    ;;

  *) echo "usage: ci-changes.sh scope|verdict" >&2; exit 2 ;;
esac
