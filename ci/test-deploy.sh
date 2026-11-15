#!/usr/bin/env bash
# Tests a template's .github/scripts/deploy.sh (factory ADR 0034): which commit a promotion picks, what it
# refuses, the pull request it opens, and what a rollout status does to the "Deploy failed" issue. Fake `gh`
# and `docker`, a throwaway git repository, no GitHub, registry or cluster.
#   ci/test-deploy.sh <template-dir>      (from the repo root; e.g. plugins/java-pipeline/templates/skeleton)
set -euo pipefail

[[ $# -eq 1 && -f "$1/.github/scripts/deploy.sh" ]] || { echo "usage: $0 <template-dir with .github/scripts/deploy.sh>" >&2; exit 2; }
t="$(cd "$1" && pwd)"
script="$t/.github/scripts/deploy.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/deploy-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }
[[ -x "$script" ]] && ok "deploy.sh is executable" || bad "deploy.sh is not executable"

# --- fakes ---------------------------------------------------------------------------------------------------
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE/calls"
expr="" args=("$@") i=0
while (( i < ${#args[@]} )); do [[ "${args[i]}" == --jq ]] && expr="${args[i+1]}"; i=$((i+1)); done
ans() { if [[ -n "$expr" ]]; then jq -r "$expr" <<<"$1"; else echo "$1"; fi; }
field() { local a; for a in "${args[@]}"; do [[ "$a" == "$1="* ]] && { echo "${a#*=}"; return; }; done; }
case "$*" in
  "api repos/acme/svc/branches/"*) [[ -e "$FAKE/branch-exists" ]] && ans '{"name":"x"}' || exit 1 ;;
  "api --method POST repos/acme/svc/git/refs "*) ans '{"ref":"r"}' ;;
  "api --method PUT repos/acme/svc/contents/"*) field content | base64 -d > "$FAKE/committed.yaml"; ans '{"commit":{"sha":"c"}}' ;;
  "api repos/acme/svc/pulls "*) b="$(field body)"; cp "${b#@}" "$FAKE/pr-body.md"; ans '{"html_url":"https://github.test/acme/svc/pull/9"}' ;;
  "api repos/acme/svc/issues?state=open"*) cat "$FAKE/issues.json" ;;
  "api repos/acme/svc/labels "*) ;;
  "api repos/acme/svc/issues "*) b="$(field body)"; cp "${b#@}" "$FAKE/issue.md"; ans '{"html_url":"https://github.test/acme/svc/issues/3"}' ;;
  "api --paginate repos/acme/svc/issues/3/comments"*) jq -r "$expr" "$FAKE/comments.json" ;;
  "api repos/acme/svc/issues/3/comments "*)
    b="$(field body)"; if [[ "$b" == @* ]]; then cp "${b#@}" "$FAKE/comment.md"; else echo "$b" > "$FAKE/comment.md"; fi
    ans '{"html_url":"u"}' ;;
  "api --method PATCH repos/acme/svc/issues/3 "*) ans '{"state":"closed"}' ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
GH
# `docker manifest inspect <image>:<commit>`: $FAKE/images has one line per commit, "<commit> <platform>...".
cat > "$work/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
[[ "$1 $2" == "manifest inspect" ]] || { echo "fake docker: unexpected call: $*" >&2; exit 1; }
echo "$3" >> "$FAKE/inspected"
line="$(grep "^${3##*:} " "$FAKE/images")" || exit 1
read -r _ plats <<<"$line"
for p in $plats; do printf '{"platform":{"os":"%s","architecture":"%s"}}\n' "${p%/*}" "${p#*/}"; done | jq -s '{manifests: .}'
DOCKER
chmod +x "$work/bin/gh" "$work/bin/docker"
export PATH="$work/bin:$PATH" FAKE="$work/fake" GH_TOKEN=t GITHUB_REPOSITORY=acme/svc
unset GITHUB_STEP_SUMMARY DEPLOY_PLATFORMS DEPLOY_STATUS_RE DEPLOY_COMMIT DEPLOY_ENV || true
reset() { rm -rf "$FAKE"; mkdir -p "$FAKE"; : > "$FAKE/calls"; : > "$FAKE/images"; echo '[]' > "$FAKE/issues.json"; echo '[]' > "$FAKE/comments.json"; }
writes() { grep -cE -- '--method (POST|PUT|PATCH)|/pulls |/issues |/comments ' "$FAKE/calls" || true; }

# --- a repository: three commits on main, one on a branch ------------------------------------------------------
repo="$work/repo"
mkdir -p "$repo" && cp -r "$t/deploy" "$repo/deploy"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }
g init -q -b main
g add deploy && g commit -q -m "first"; c1="$(g rev-parse HEAD)"
echo a > "$repo/a.txt" && g add a.txt && g commit -q -m "second: a feature"; c2="$(g rev-parse HEAD)"
echo b > "$repo/b.txt" && g add b.txt && g commit -q -m "third: another"; c3="$(g rev-parse HEAD)"
g switch -q -c side && echo s > "$repo/s.txt" && g add s.txt && g commit -q -m "on a branch"; side="$(g rev-parse HEAD)"
g switch -q main
both="linux/amd64 linux/arm64"
promote() { (cd "$repo" && DEPLOY_MAIN=main DEPLOY_ENV="${ENVN:-staging}" DEPLOY_COMMIT="${COMMIT:-}" "$script" promote) > "$work/out" 2>&1; }
refused() { # refused <description> <text the message must hold>
  if promote; then bad "$1: it was not refused"; return; fi
  grep -q -- "$2" "$work/out" || { bad "$1: wrong reason: $(tail -n 1 "$work/out")"; return; }
  [[ "$(writes)" == 0 ]] && ok "$1: refused, nothing written" || bad "$1: refused, but GitHub was written to"
}
tag_of() { sed -n 's/^ *newTag: *//p' "$1" | head -n 1; }

# 1. No commit named: the newest one whose image has every platform (c3 is amd64 only, as before 0.22.0).
reset; printf '%s\n' "$c3 linux/amd64" "$c2 $both" "$c1 $both" > "$FAKE/images"
if promote; then
  [[ "$(tag_of "$FAKE/committed.yaml")" == "$c2" ]] && ok "promote: picks the newest commit with an image for both platforms" \
    || bad "promote: committed tag is $(tag_of "$FAKE/committed.yaml"), wanted $c2"
  diff <(sed "s/newTag: .*/newTag: X/" "$FAKE/committed.yaml") <(sed "s/newTag: .*/newTag: X/" "$repo/deploy/k8s/overlays/staging/kustomization.yaml") >/dev/null \
    && ok "promote: only the tag line of the staging overlay changes" || bad "promote: the overlay changed elsewhere"
  grep -q "git/refs -f ref=refs/heads/promote/staging-${c2:0:12} -f sha=$c3" "$FAKE/calls" \
    && ok "promote: the branch starts at main's head" || bad "promote: wrong branch or start: $(grep git/refs "$FAKE/calls")"
  grep -q "contents/deploy/k8s/overlays/staging/kustomization.yaml " "$FAKE/calls" && ! grep -q "overlays/prod" "$FAKE/calls" \
    && ok "promote: commits to the staging overlay, not prod" || bad "promote: wrong file committed"
  grep -q "pulls -f title=deploy(staging): promote to ${c2:0:12} -f head=promote/staging-${c2:0:12} -f base=main" "$FAKE/calls" \
    && ok "promote: opens the pull request against main" || bad "promote: wrong pull request: $(grep '/pulls ' "$FAKE/calls")"
  grep -q 'First promotion' "$FAKE/pr-body.md" && grep -q "$c2" "$FAKE/pr-body.md" \
    && ok "promote: the body says it is the first promotion" || bad "promote: body: $(cat "$FAKE/pr-body.md")"
  grep -q 'https://github.test/acme/svc/pull/9' "$work/out" && ok "promote: prints the pull request" || bad "promote: no URL printed"
else bad "promote: newest image: $(tail -n 1 "$work/out")"; fi

# 2. A later promotion lists what rolls out; a rollback says so.
sed -i "s/newTag: .*/newTag: $c1/" "$repo/deploy/k8s/overlays/staging/kustomization.yaml"
g add deploy && g commit -q -m "deploy(staging): c1"; c4="$(g rev-parse HEAD)"
reset; printf '%s\n' "$c3 $both" "$c2 $both" "$c1 $both" > "$FAKE/images"
if COMMIT="${c3:0:10}" promote; then
  [[ "$(tag_of "$FAKE/committed.yaml")" == "$c3" ]] && ok "promote: a short commit id becomes the full one" || bad "promote: short id gave $(tag_of "$FAKE/committed.yaml")"
  grep -q 'second: a feature' "$FAKE/pr-body.md" && grep -q 'third: another' "$FAKE/pr-body.md" \
    && ok "promote: the body lists the commits that roll out" || bad "promote: body lacks the commits: $(cat "$FAKE/pr-body.md")"
else bad "promote: named commit: $(tail -n 1 "$work/out")"; fi
sed -i "s/newTag: .*/newTag: $c3/" "$repo/deploy/k8s/overlays/staging/kustomization.yaml"
g add deploy && g commit -q -m "deploy(staging): c3"
reset; printf '%s\n' "$c3 $both" "$c2 $both" > "$FAKE/images"
if COMMIT="$c2" promote; then
  grep -q 'rollback' "$FAKE/pr-body.md" && ok "promote: an older commit is called a rollback" || bad "promote: rollback not named"
else bad "promote: rollback: $(tail -n 1 "$work/out")"; fi

# 3. What it refuses (staging is at c3 now).
reset; printf '%s\n' "$c3 $both" > "$FAKE/images"
refused "the tag the environment already has" "already at"
reset; printf '%s\n' "$c2 linux/amd64" > "$FAKE/images"
COMMIT="$c2" refused "a commit whose image lacks arm64" "no linux/arm64 image"
reset
COMMIT="$c2" refused "a commit with no image" "no image"
reset; printf '%s\n' "$side $both" > "$FAKE/images"
COMMIT="$side" refused "a commit that is not on main" "is not on main"
reset
COMMIT="nonsense" refused "something that is no commit" "is not a commit"
reset
refused "no commit on main with an image" "none of the last 50"
reset; printf '%s\n' "$c2 $both" > "$FAKE/images"
ENVN=qa refused "an environment with no overlay" "no overlay"
ENVN='../prod' refused "an environment name with a path in it" "not an environment name"
reset; printf '%s\n' "$c2 $both" > "$FAKE/images"; touch "$FAKE/branch-exists"
COMMIT="$c2" refused "a promotion whose branch exists" "already has a pull request"
# prod is still unreleased: promoting it is independent of staging.
reset; printf '%s\n' "$c3 $both" > "$FAKE/images"
if ENVN=prod promote && grep -q "contents/deploy/k8s/overlays/prod/kustomization.yaml " "$FAKE/calls"; then
  ok "promote: prod is promoted by itself"; else bad "promote: prod: $(tail -n 1 "$work/out")"; fi

# --- report: a rollout status and the issue ------------------------------------------------------------------
sha=1111111111111111111111111111111111111111 sha2=2222222222222222222222222222222222222222
report() { # report <context> <state> <sha> [description]
  (cd "$work" && DEPLOY_CONTEXT="$1" DEPLOY_STATE="$2" DEPLOY_SHA="$3" DEPLOY_DESCRIPTION="${4:-}" "$script" report) > "$work/out" 2>&1
}
open_issue='[{"number":8,"title":"Deploy failed: flux/other","body":"x"},{"number":3,"title":"Deploy failed: flux/svc-staging","body":"commit '"$sha"'"}]'

reset; report "CodeQL" failure "$sha" && [[ ! -s "$FAKE/calls" ]] && ok "report: another context is ignored without a call" || bad "report: another context made calls"
reset; report "flux/svc-staging" pending "$sha" && [[ "$(writes)" == 0 ]] && ok "report: pending writes nothing" || bad "report: pending wrote"
reset; report "flux/svc-staging" success "$sha" && [[ "$(writes)" == 0 ]] && ok "report: a success with no open issue writes nothing" || bad "report: success wrote"

reset
if report "flux/svc-staging" failure "$sha" 'health check failed `rm -rf /` $(touch '"$work"'/pwned) @someone fixes #1'; then
  grep -q 'issues -f title=Deploy failed: flux/svc-staging -f labels\[\]=deploy-failed' "$FAKE/calls" \
    && ok "report: a failure opens the labelled issue" || bad "report: no issue opened: $(cat "$FAKE/calls")"
  grep -q "$sha" "$FAKE/issue.md" && grep -q 'health check failed' "$FAKE/issue.md" && ok "report: the issue names the commit and Flux's message" || bad "report: issue body: $(cat "$FAKE/issue.md")"
  [[ ! -e "$work/pwned" ]] && ! grep -q '[`@#]someone\|@someone\|#1' "$FAKE/issue.md" \
    && ok "report: the message is text: nothing runs, no mention, no issue reference" || bad "report: the message was not neutralised: $(cat "$FAKE/issue.md")"
else bad "report: failure: $(tail -n 1 "$work/out")"; fi

reset; echo "$open_issue" > "$FAKE/issues.json"
report "flux/svc-staging" failure "$sha" "again" && [[ "$(writes)" == 0 ]] \
  && ok "report: the same commit failing again adds nothing" || bad "report: repeated failure wrote: $(cat "$FAKE/calls")"
reset; echo "$open_issue" > "$FAKE/issues.json"; echo '[{"body":"It failed again, now at commit '"$sha2"'."}]' > "$FAKE/comments.json"
report "flux/svc-staging" error "$sha2" "again" && [[ "$(writes)" == 0 ]] \
  && ok "report: a commit already in a comment adds nothing" || bad "report: commented twice for one commit"
reset; echo "$open_issue" > "$FAKE/issues.json"
if report "flux/svc-staging" failure "$sha2" "still broken"; then
  grep -q "$sha2" "$FAKE/comment.md" && ! grep -q 'issues -f title' "$FAKE/calls" \
    && ok "report: another commit failing comments on the open issue" || bad "report: new commit: $(cat "$FAKE/calls")"
else bad "report: new failing commit: $(tail -n 1 "$work/out")"; fi
reset; echo "$open_issue" > "$FAKE/issues.json"
if report "flux/svc-staging" success "$sha2"; then
  grep -q 'PATCH repos/acme/svc/issues/3 -f state=closed' "$FAKE/calls" && grep -q "$sha2" "$FAKE/comment.md" && ! grep -q 'issues/8' "$FAKE/calls" \
    && ok "report: a success comments and closes that context's issue only" || bad "report: success: $(cat "$FAKE/calls")"
else bad "report: success with an issue: $(tail -n 1 "$work/out")"; fi

# --- the workflows ---------------------------------------------------------------------------------------------
pw="$t/.github/workflows/promote.yml" dw="$t/.github/workflows/post-deploy.yml" ci="$t/.github/workflows/ci.yml"
if [[ -f "$pw" && -f "$dw" ]]; then
  ok "promote.yml and post-deploy.yml exist"
  grep -q 'deploy\.sh promote' "$pw" && grep -q 'deploy\.sh report' "$dw" && ok "the workflows call the script" || bad "a workflow does not call deploy.sh"
  ! grep -qE '^\s+run:.*\$\{\{' "$pw" "$dw" && ok "no run command interpolates an expression" || bad "a run command interpolates an expression (pass it through env)"
  grep -qE '^on:\s*$' "$pw" && grep -qE '^  workflow_dispatch:' "$pw" && ! grep -qE '^  (push|pull_request|schedule)' "$pw" \
    && ok "promote.yml only starts by hand" || bad "promote.yml has another trigger"
  grep -qE '^  status:' "$dw" && ok "post-deploy.yml runs on commit statuses" || bad "post-deploy.yml is not triggered by status"
  ! grep -qE '(contents|pull-requests|actions|packages): write' "$dw" && grep -q 'issues: write' "$dw" \
    && ok "post-deploy.yml may write issues only" || bad "post-deploy.yml asks for more than issues: write"
  grep -q "persist-credentials: false" "$pw" && grep -q "persist-credentials: false" "$dw" \
    && ok "neither workflow leaves credentials in the checkout" || bad "a checkout keeps its credentials"
else
  bad "missing promote.yml or post-deploy.yml"
fi
flat="$(tr -s '\n' ' ' < "$ci")"
grep -q 'jib:build -Djib.from.platforms=linux/amd64,linux/arm64 -Djib.container.format=Docker ' <<<"$flat" && ok "ci.yml pushes the image for amd64 and arm64" || bad "ci.yml does not push both platforms"
grep -qE 'for arch in amd64 arm64' "$ci" && [[ "$(grep -c 'jib-image-\$arch\|oci-image-\$arch' "$ci")" -ge 3 ]] \
  && ok "ci.yml scans the image of each platform" || bad "ci.yml does not scan each platform's image"
grep -qE 'cosign sign --yes --recursive' "$ci" && ok "ci.yml signs the index and each platform's image" || bad "ci.yml does not sign recursively"

[[ $fails -eq 0 ]] && echo "deploy tests: OK ($(basename "$t"))"
exit $fails
