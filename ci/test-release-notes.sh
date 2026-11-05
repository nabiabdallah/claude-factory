#!/usr/bin/env bash
# Tests ci/check-release-notes.sh (factory ADR 0015) on a throwaway copy of the versioned files: a version bump
# without a changelog section, a section without a bump, and release tags that don't match.
#   ci/test-release-notes.sh        (from the repo root)
set -euo pipefail

root="$(pwd)"
[[ -f ci/check-release-notes.sh ]] || { echo "run from the repo root" >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/release-notes-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
files=(ci/check-release-notes.sh plugins/java-pipeline/.claude-plugin/plugin.json plugins/java-pipeline/CHANGELOG.md
  parents/factory-parent/pom.xml parents/factory-parent/CHANGELOG.md)
fails=0

fresh() {
  rm -rf "$work/r"
  for f in "${files[@]}"; do
    mkdir -p "$work/r/$(dirname "$f")"
    cp "$root/$f" "$work/r/$f"
  done
  cd "$work/r"
}
expect() { # expect pass|fail <description> [args...]
  local want="$1" desc="$2" got out
  shift 2
  if out="$(ci/check-release-notes.sh "$@" 2>&1)"; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc (expected $want, got $got)"
    sed 's/^/    /' <<<"$out"
    fails=1
  fi
  cd "$root"
}
plugin_version() { sed -n 's/^ *"version": "\(.*\)",$/\1/p' plugins/java-pipeline/.claude-plugin/plugin.json; }
parent_version() { sed -n '/<artifactId>factory-parent<\/artifactId>/{n;s|.*<version>\(.*\)</version>.*|\1|p}' parents/factory-parent/pom.xml; }

fresh
expect pass "versions and changelogs agree"

fresh
sed -i 's/^\( *"version": "\)[^"]*/\19.9.9/' plugins/java-pipeline/.claude-plugin/plugin.json
expect fail "plugin version bumped without a changelog section"

fresh
sed -i "0,/^## \[/s//## [9.9.9] - 2099-01-01\n\n- Notes without a version bump.\n\n## [/" plugins/java-pipeline/CHANGELOG.md
expect fail "plugin changelog section without a version bump"

fresh
sed -i '/<artifactId>factory-parent<\/artifactId>/{n;s|<version>[^<]*</version>|<version>9.9.9</version>|}' parents/factory-parent/pom.xml
expect fail "factory-parent version bumped without a changelog section"

fresh
v="$(plugin_version)"
expect pass "release tag java-pipeline-v$v matches" --tag "java-pipeline-v$v"

fresh
v="$(plugin_version)"
out="$(ci/check-release-notes.sh --notes "java-pipeline-v$v" 2>/dev/null || true)"
cd "$root"
if [[ -n "$out" && "$out" != *"## ["* ]]; then
  echo "ok   - --notes prints only that version's section"
else
  echo "FAIL - --notes output: '$out'"
  fails=1
fi

fresh
v="$(parent_version)"
expect pass "release tag factory-parent-v$v matches" --tag "factory-parent-v$v"

fresh
expect fail "release tag for another version" --tag "java-pipeline-v0.0.1"

fresh
expect fail "release tag for an unknown component" --tag "other-plugin-v1.0.0"

fresh
sed -i 's/^\( *"version": "\)[^"]*/\19.9.9/' plugins/java-pipeline/.claude-plugin/plugin.json
expect fail "release tag matching a version with no section" --tag "java-pipeline-v9.9.9"

[[ "$fails" -eq 0 ]] && echo "release-notes: all cases behave as expected" || { echo "release-notes: test FAILED"; exit 1; }
