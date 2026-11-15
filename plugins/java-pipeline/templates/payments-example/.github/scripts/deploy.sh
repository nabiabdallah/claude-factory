#!/usr/bin/env bash
# Promotions and their result (claude-factory ADRs 0012 and 0034). The cluster pulls: Flux applies the overlay of
# each environment from the default branch, so deploying is merging a pull request that changes that overlay's
# newTag, and GitHub holds no cluster credentials.
#   promote   (.github/workflows/promote.yml, started by a person) open that pull request. DEPLOY_ENV names the
#             overlay. DEPLOY_COMMIT is the commit to promote; without it, the newest commit on the default
#             branch that has an image for every platform in $platforms. check-deploy.sh judges the pull request
#             in CI as it would a hand-made one; a person merges it (deploy files are risk:high).
#   report    (.github/workflows/post-deploy.yml, on a commit status) Flux reports each rollout as a commit status
#             on the commit it applied. A failed one opens the issue "Deploy failed: <context>" (once per commit;
#             a later commit that also fails adds a comment); a success closes it.
# Tested with a fake `gh` and a fake `docker` by claude-factory's ci/test-deploy.sh.
set -euo pipefail

# The platforms a commit's image must have before it can be promoted: CI's and the cluster's.
platforms="${DEPLOY_PLATFORMS:-linux/amd64 linux/arm64}"
# Which commit statuses are rollout results.
status_re="${DEPLOY_STATUS_RE:-^(flux|kustomization)/}"
label=deploy-failed

say() { echo "deploy: $*"; [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "$*" >> "$GITHUB_STEP_SUMMARY"; }
die() { echo "deploy: $*" >&2; [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "Stopped: $*" >> "$GITHUB_STEP_SUMMARY"; exit 1; }
need() { local v; for v in "$@"; do [[ -n "${!v:-}" ]] || die "$v is not set"; done; }
work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/deploy.XXXXXX")"
trap 'rm -rf "$work"' EXIT

case "${1:-}" in
  promote)
    need GITHUB_REPOSITORY GH_TOKEN DEPLOY_ENV
    repo="$GITHUB_REPOSITORY" env="$DEPLOY_ENV" base="${DEPLOY_BASE_BRANCH:-main}"
    main="${DEPLOY_MAIN:-origin/$base}"
    [[ "$env" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "'$env' is not an environment name"
    overlay="deploy/k8s/overlays/$env/kustomization.yaml"
    git cat-file -e "$main:$overlay" 2>/dev/null || die "no overlay for '$env' on $base ($overlay)"
    git show "$main:$overlay" > "$work/old.yaml"
    image="$(awk '/^images:/ {f=1; next} f && /name:/ {print $NF; exit}' "$work/old.yaml")"
    current="$(sed -n 's/^ *newTag: *//p' "$work/old.yaml" | head -n 1)"
    [[ -n "$image" && -n "$current" ]] || die "$overlay has no image with a newTag"

    missing=""
    has_image() { # <commit>: its image exists for every platform; otherwise $missing says what is absent
      local manifest have p
      manifest="$(docker manifest inspect "$image:$1" 2>/dev/null)" || { missing="no image"; return 1; }
      have="$(jq -r '[.manifests[]?.platform | "\(.os)/\(.architecture)"] | join(" ")' <<<"$manifest")"
      for p in $platforms; do
        [[ " $have " == *" $p "* ]] || { missing="no $p image"; return 1; }
      done
    }
    if [[ -n "${DEPLOY_COMMIT:-}" ]]; then
      sha="$(git rev-parse --verify --quiet "$DEPLOY_COMMIT^{commit}")" || die "'$DEPLOY_COMMIT' is not a commit of this repository"
      git merge-base --is-ancestor "$sha" "$main" || die "$sha is not on $base"
      has_image "$sha" || die "$image:$sha: $missing. CI pushes the image after a green build on $base; wait for it, or name a commit that has one."
    else
      sha=""
      for c in $(git rev-list --first-parent -n 50 "$main"); do
        if has_image "$c"; then sha="$c"; break; fi
      done
      [[ -n "$sha" ]] || die "none of the last 50 commits on $base has an image for: $platforms"
    fi
    [[ "$sha" != "$current" ]] || die "$env is already at $sha"

    branch="promote/$env-${sha:0:12}"
    if gh api "repos/$repo/branches/${branch//\//%2F}" --jq .name >/dev/null 2>&1; then
      die "the branch $branch exists: this promotion already has a pull request (or delete the branch)"
    fi
    sed "0,/^\( *newTag: *\).*/s//\1$sha/" "$work/old.yaml" > "$work/new.yaml"

    {
      printf 'Promotes **%s** from `%s` to `%s`.\n\n' "$env" "$current" "$sha"
      if [[ "$current" =~ ^[0-9a-f]{40}$ ]] && git cat-file -e "$current^{commit}" 2>/dev/null; then
        if git merge-base --is-ancestor "$current" "$sha"; then
          n="$(git rev-list --count --no-merges "$current..$sha")"
          printf 'Changes that roll out (%s, newest first%s):\n\n' "$n" "$( ((n > 30)) && echo ', the first 30' || true)"
          git log --no-merges -n 30 --format='- %h %s' "$current..$sha"
        else
          printf 'This is a **rollback**: `%s` is older than what runs now.\n' "${sha:0:12}"
        fi
      else
        printf 'First promotion of this environment: nothing runs there yet.\n'
      fi
      printf '\nMerging this pull request is the deploy: the cluster applies `%s` within about a minute and ' "$overlay"
      printf 'reports the rollout as a commit status on the merge commit. A failed rollout opens an issue here; the '
      printf 'version that runs now keeps serving.\n\nThe `manifests` check applies the promotion rules '
      printf '(`.github/scripts/check-deploy.sh`). If it asks for `components/recreate`, add it on this branch.\n'
    } > "$work/body.md"

    gh api --method POST "repos/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$(git rev-parse "$main")" \
      --jq .ref >/dev/null || die "could not create the branch $branch"
    gh api --method PUT "repos/$repo/contents/$overlay" -f message="deploy($env): promote to ${sha:0:12}" \
      -f branch="$branch" -f sha="$(git rev-parse "$main:$overlay")" -f content="$(base64 -w 0 "$work/new.yaml")" \
      --jq .commit.sha >/dev/null || die "could not commit the new tag on $branch"
    pr_url="$(gh api "repos/$repo/pulls" -f title="deploy($env): promote to ${sha:0:12}" -f head="$branch" \
      -f base="$base" -F body=@"$work/body.md" --jq .html_url)" || die "GitHub refused the pull request (the branch $branch is pushed)"
    [[ -n "$pr_url" ]] || die "the pull request was not created"
    say "Opened $pr_url: $env from $current to $sha."
    # A pull request opened with a workflow's own token starts no CI (claude-factory ADR 0028).
    [[ "${DEPLOY_PR_STARTS_CI:-true}" == true ]] \
      || say "CI does not start on it by itself: close and reopen the pull request, or give this repository the factory's App."
    ;;

  report)
    need GITHUB_REPOSITORY GH_TOKEN DEPLOY_CONTEXT DEPLOY_STATE DEPLOY_SHA
    repo="$GITHUB_REPOSITORY" context="$DEPLOY_CONTEXT" sha="$DEPLOY_SHA"
    [[ "$context" =~ $status_re ]] || { echo "deploy: '$context' is not a rollout status; nothing to do"; exit 0; }
    title="Deploy failed: $context"
    # Flux's message is text from outside: one line, no markup that could mention people or close issues.
    why="$(tr -s '\r\n\t' '   ' <<<"${DEPLOY_DESCRIPTION:-}" | tr -d '`@#<>' | cut -c1-500)"
    gh api "repos/$repo/issues?state=open&labels=$label&per_page=100" > "$work/issues.json" \
      || die "could not list the open $label issues"
    issue="$(jq -r --arg t "$title" '[.[] | select(.pull_request == null and .title == $t)][0].number // empty' "$work/issues.json")"

    case "$DEPLOY_STATE" in
      failure|error)
        if [[ -z "$issue" ]]; then
          gh api "repos/$repo/labels" -f name="$label" -f color=b60205 \
            -f description="A rollout failed on the cluster" >/dev/null 2>&1 || true # it exists already
          {
            printf 'The cluster could not roll out commit %s (`%s`).\n\n' "$sha" "$context"
            printf 'What it said: %s\n\n' "${why:-(nothing)}"
            printf 'The version that ran before keeps serving: a rolling update only replaces pods that become '
            printf 'ready. Fix it with a new promotion, or revert the pull request that promoted this commit.\n\n'
            printf 'This issue closes itself when `%s` reports a success.\n' "$context"
          } > "$work/issue.md"
          url="$(gh api "repos/$repo/issues" -f title="$title" -f "labels[]=$label" -F body=@"$work/issue.md" --jq .html_url)" \
            || die "could not open the issue"
          say "Rollout failed ($context at $sha): opened $url"
        else
          { jq -r --argjson n "$issue" '.[] | select(.number == $n) | .body // ""' "$work/issues.json"
            gh api --paginate "repos/$repo/issues/$issue/comments?per_page=100" --jq '.[].body'; } > "$work/seen.txt" \
            || die "could not read issue #$issue"
          if grep -qF "$sha" "$work/seen.txt"; then
            echo "deploy: issue #$issue already reports $sha"
          else
            printf 'It failed again, now at commit %s.\n\nWhat it said: %s\n' "$sha" "${why:-(nothing)}" > "$work/comment.md"
            gh api "repos/$repo/issues/$issue/comments" -F body=@"$work/comment.md" --jq .html_url >/dev/null \
              || die "could not comment on issue #$issue"
            say "Rollout failed again ($context at $sha): added to issue #$issue"
          fi
        fi
        ;;
      success)
        if [[ -n "$issue" ]]; then
          gh api "repos/$repo/issues/$issue/comments" -f body="Rolled out: commit $sha is running." --jq .html_url >/dev/null \
            || die "could not comment on issue #$issue"
          gh api --method PATCH "repos/$repo/issues/$issue" -f state=closed -f state_reason=completed --jq .state >/dev/null \
            || die "could not close issue #$issue"
          say "Rollout succeeded ($context at $sha): closed issue #$issue"
        else
          echo "deploy: $context succeeded at $sha"
        fi
        ;;
      *) echo "deploy: state '$DEPLOY_STATE' needs no report" ;;
    esac
    ;;

  *) echo "usage: deploy.sh promote|report" >&2; exit 2 ;;
esac
