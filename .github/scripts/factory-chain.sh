#!/usr/bin/env bash
# Chaining and releases in the factory repo (factory ADR 0026). Two phases, each called by its own workflow:
#   next-step   (factory-chain.yml: a merge that changed docs/ROADMAP.md, once a day, or by hand)
#               dispatches factory-step.yml for the first unfinished queue step, unless the factory is paused, a
#               step PR is open, its branch exists, a step run is queued or running, or the last step run failed
#               on this same commit. Every "no" is a green run that says why in the job summary.
#   release     (release-tag.yml: a merge that changed a component's version)
#               creates the tag <component>-v<version> on the merged commit when it doesn't exist yet and the
#               changelog has its section. The tag is created with the factory App's token: a tag pushed with
#               GITHUB_TOKEN would not start release-plugin.yml or publish-parent.yml.
# Tested with a fake `gh` by ci/test-factory-chain.sh.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
die() { echo "factory-chain: $*" >&2; [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "Stopped: $*" >> "$GITHUB_STEP_SUMMARY"; exit 1; }
need() { local v; for v in "$@"; do [[ -n "${!v:-}" ]] || die "$v is not set"; done; }
say() { echo "factory-chain: $*"; [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "$*" >> "$GITHUB_STEP_SUMMARY"; }
skip() { say "No step started: $*"; exit 0; }

case "${1:-}" in
  next-step)
    need GITHUB_REPOSITORY GITHUB_SHA GH_TOKEN
    [[ "${FACTORY_PAUSED:-}" != true ]] || skip "the factory is paused (repository variable FACTORY_PAUSED=true)"
    step="$("$here/factory-step.sh" queue | head -n 1)"
    [[ -n "$step" ]] || skip "no unfinished step in the roadmap's queue"
    branch="factory/step-${step,,}"

    prs="$(gh pr list --repo "$GITHUB_REPOSITORY" --state open --json headRefName --jq '.[].headRefName')" \
      || die "could not list the open pull requests"
    open="$(grep '^factory/step-' <<<"$prs" || true)"
    [[ -z "$open" ]] || skip "a step PR is still open ($(tr '\n' ' ' <<<"$open")): one step at a time"
    if gh api "repos/$GITHUB_REPOSITORY/branches/${branch//\//%2F}" --jq .name >/dev/null 2>&1; then
      skip "branch $branch already exists: delete it to let step $step run again"
    fi

    # The newest step run: "<status> <conclusion> <head sha>", or nothing if there never was one.
    last="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/factory-step.yml/runs?per_page=1" \
      --jq '.workflow_runs[0] // empty | [.status, (.conclusion // "none"), .head_sha] | join(" ")')" \
      || die "could not read the step runs"
    if [[ -n "$last" ]]; then
      read -r status conclusion sha <<<"$last"
      [[ "$status" == completed ]] || skip "a step run is already queued or running"
      # A run that failed says why in its summary. Running it again on the same commit would only spend usage.
      [[ "$conclusion" == success || "$sha" != "$GITHUB_SHA" ]] \
        || skip "the last step run ended as '$conclusion' on this commit and nothing has merged since: fix the cause, or start factory-step.yml by hand"
    fi

    gh api --method POST "repos/$GITHUB_REPOSITORY/actions/workflows/factory-step.yml/dispatches" \
      -f ref="${FACTORY_REF:-main}" -f "inputs[step]=$step" >/dev/null || die "could not dispatch factory-step.yml for $step"
    say "Started step $step (factory-step.yml)"
    ;;

  release)
    need GITHUB_REPOSITORY GITHUB_SHA GH_TOKEN
    [[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] || die "unexpected commit '$GITHUB_SHA'"
    tags="$(ci/check-release-notes.sh --tags)" || die "could not read the components' versions"
    while IFS= read -r tag; do
      [[ -n "$tag" ]] || continue
      # Only plain X.Y.Z versions are released (a -SNAPSHOT or pre-release version is work in progress).
      [[ "$tag" =~ ^[a-z][a-z-]*-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { say "Not tagged: $tag is not a release version"; continue; }
      if found="$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$tag" --jq .ref 2>&1)"; then
        echo "factory-chain: $tag exists"; continue
      fi
      grep -q 'HTTP 404' <<<"$found" || die "could not check whether $tag exists: $found"
      ci/check-release-notes.sh --tag "$tag" || die "$tag: the changelog has no section for this version"
      gh api --method POST "repos/$GITHUB_REPOSITORY/git/refs" -f ref="refs/tags/$tag" -f sha="$GITHUB_SHA" >/dev/null \
        || die "could not create the tag $tag"
      say "Tagged $tag on $GITHUB_SHA; its release workflow follows"
    done <<<"$tags"
    ;;

  *) echo "usage: factory-chain.sh next-step|release" >&2; exit 2 ;;
esac
