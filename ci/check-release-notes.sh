#!/usr/bin/env bash
# Release notes check (factory ADR 0015). Run from the repo root.
#   ci/check-release-notes.sh                 every PR: each component's newest changelog section is its version
#   ci/check-release-notes.sh --tag <tag>     release: <component>-v<version> matches the component and has notes
#   ci/check-release-notes.sh --notes <tag>   as --tag, then prints that version's notes (the GitHub Release body)
# Components: java-pipeline (plugin.json), factory-parent (pom.xml). Changelogs: Keep a Changelog,
# sections "## [X.Y.Z] - YYYY-MM-DD", newest first; an "## [Unreleased]" section is ignored.
set -euo pipefail

version_of() {
  case "$1" in
    java-pipeline) sed -n 's/^ *"version": "\(.*\)",$/\1/p' plugins/java-pipeline/.claude-plugin/plugin.json | sed -n 1p ;;
    factory-parent) sed -n '/<artifactId>factory-parent<\/artifactId>/{n;s|.*<version>\(.*\)</version>.*|\1|p}' parents/factory-parent/pom.xml | sed -n 1p ;;
    *) return 1 ;;
  esac
}
changelog_of() {
  case "$1" in
    java-pipeline) echo plugins/java-pipeline/CHANGELOG.md ;;
    factory-parent) echo parents/factory-parent/CHANGELOG.md ;;
  esac
}
newest_section() { sed -n 's/^## \[\([0-9][^]]*\)\] - [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$/\1/p' "$1" | sed -n 1p; }
section() { # section <changelog> <version>: the body of that version's section
  awk -v v="$2" '
    $0 ~ "^## \\[" { if (found) exit; if (index($0, "## [" v "] - ") == 1) { found = 1; next } }
    found { print }
  ' "$1" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
}

fail=0
problem() { echo "FAIL: $*" >&2; fail=1; }

check_component() { # check_component <name>: newest section == version, and it has content
  local name="$1" version changelog newest
  version="$(version_of "$name")"
  changelog="$(changelog_of "$name")"
  [[ -n "$version" ]] || { problem "$name: no version found"; return; }
  [[ -f "$changelog" ]] || { problem "$name: $changelog is missing"; return; }
  newest="$(newest_section "$changelog")"
  if [[ "$newest" != "$version" ]]; then
    problem "$name is $version but the newest section of $changelog is '${newest:-none}': bump both together"
  elif [[ -z "$(section "$changelog" "$version")" ]]; then
    problem "$name: the [$version] section of $changelog is empty"
  fi
}

case "${1:-}" in
  "")
    check_component java-pipeline
    check_component factory-parent
    [[ "$fail" -eq 0 ]] && echo "release notes: OK"
    exit "$fail"
    ;;
  --tag|--notes)
    tag="${2:-}"
    [[ "$tag" =~ ^([a-z][a-z-]*)-v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || { problem "not a release tag: '$tag'"; exit 1; }
    name="${BASH_REMATCH[1]}"
    tag_version="${BASH_REMATCH[2]}"
    version="$(version_of "$name")" || { problem "unknown component '$name' in tag $tag"; exit 1; }
    [[ "$version" == "$tag_version" ]] || { problem "tag $tag but $name is $version"; exit 1; }
    check_component "$name"
    [[ "$fail" -eq 0 ]] || exit 1
    if [[ "$1" == --notes ]]; then
      section "$(changelog_of "$name")" "$version"
    else
      echo "release tag $tag: OK"
    fi
    ;;
  *)
    echo "usage: $0 [--tag <tag> | --notes <tag>]" >&2
    exit 2
    ;;
esac
