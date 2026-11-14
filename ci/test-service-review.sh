#!/usr/bin/env bash
# Tests a template's .github/scripts/risk-tier.sh (factory ADR 0033): the service path lists, labels, which PRs
# get the independent review (every PR from a branch of the repo, any tier), the review comment (one per PR,
# replaced on each new head), and the merge, which only a risk:low PR with green required checks and an APPROVE
# gets. Fake `gh`, stand-in reviewer, no GitHub or Claude credential.
#   ci/test-service-review.sh <template-dir>      (from the repo root; e.g. plugins/java-pipeline/templates/skeleton)
set -euo pipefail

[[ $# -eq 1 && -x "$1/.github/scripts/risk-tier.sh" ]] || { echo "usage: $0 <template-dir with .github/scripts/risk-tier.sh>" >&2; exit 2; }
t="$(cd "$1" && pwd)"
script="$t/.github/scripts/risk-tier.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/service-review-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }
rt() { "$script" "$@"; }

# --- classify: every path class of a service -------------------------------------------------------------------
tier() { # tier <author> <title> <paths...> -> the first output line
  local a="$1" ti="$2" out; shift 2
  out="$(printf '%s\n' "$@" | PR_AUTHOR="$a" PR_TITLE="$ti" rt classify)"
  head -n 1 <<<"$out"
}
expect() { # expect <low|high> <description> <author> <title> <paths...>
  local want="$1" what="$2" a="$3" ti="$4" got; shift 4
  got="$(tier "$a" "$ti" "$@")"
  [[ "$got" == "$want" ]] && ok "classify: $what -> $want" || bad "classify: $what: wanted $want, got $got"
}
dep='dependabot[bot]'
expect low  "docs"                            me "docs" README.md docs/adr/0003-x.md docs/runbook.md
expect low  "tests"                           me "tests" src/test/java/io/x/RatesServiceTest.java src/test/resources/a.json
expect high "production code"                 me "feat" src/main/java/io/x/Rates.java
expect high "main resources (config)"         me "feat" src/main/resources/application.properties
expect high "a spec (merging it starts a build)" me "spec" docs/specs/0002-x.md
expect high "the architecture test"           me "test" src/test/java/io/x/ArchitectureTest.java
expect high "another ArchUnit test"           me "test" src/test/java/io/x/ProviderIsolationArchTest.java
expect high "the build"                       me "build" pom.xml
expect high "the Maven wrapper"               me "build" .mvn/wrapper/maven-wrapper.properties
expect high "a workflow"                      me "ci" .github/workflows/ci.yml
expect high "this classifier"                 me "ci" .github/scripts/risk-tier.sh
expect high "agent rules"                     me "docs" CLAUDE.md
expect high "agent settings"                  me "chore" .claude/settings.json
expect high "deploy files"                    me "deploy" deploy/k8s/base/deployment.yaml
expect high "a migration"                     me "db" src/main/resources/db/migration/V2__x.sql
expect high "a test with a sensitive word"    me "test" src/test/java/io/x/TokenValidatorTest.java
expect high "a path it doesn't know"          me "chore" scripts/run.sh
expect high "docs and code mixed"             me "feat" README.md src/main/java/io/x/A.java
expect high "no files"                        me "x"
expect low  "dependabot minor, a dependency"  "$dep" "build(deps): bump org.foo:bar from 1.2.0 to 1.3.0" pom.xml
expect low  "dependabot patch, an action pin" "$dep" "ci: bump actions/checkout from 7.0.0 to 7.0.1" .github/workflows/ci.yml
expect high "dependabot major"                "$dep" "build(deps): bump org.foo:bar from 1.9.0 to 2.0.0" pom.xml
expect high "dependabot group (no versions)"  "$dep" "build(deps): bump the maven group with 3 updates" pom.xml
expect high "dependabot bumping factory-parent" "$dep" "build(deps): bump io.github.nabiabdallah.factory:factory-parent from 2.1.1 to 2.2.0" pom.xml
expect high "dependabot touching the review workflow" "$dep" "ci: bump actions/checkout from 7.0.0 to 7.0.1" .github/workflows/factory-review.yml
expect high "a person's bump title is no Dependabot" me "build(deps): bump org.foo:bar from 1.2.0 to 1.3.0" pom.xml

# --- the pull request side, with a fake gh -------------------------------------------------------------------
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH/calls"
expr="" args=("$@") i=0
while (( i < ${#args[@]} )); do [[ "${args[i]}" == --jq ]] && expr="${args[i+1]}"; i=$((i+1)); done
ans() { if [[ -n "$expr" ]]; then jq -r "$expr" "$1"; else cat "$1"; fi; }
case "$*" in
  "api repos/acme/svc/pulls/7") cat "$FAKE_GH/pr.json" ;;
  "api repos/acme/svc/commits/"*"/pulls "*) ans "$FAKE_GH/commit-pulls.json" ;;
  "api --paginate repos/acme/svc/pulls/7/files "*) ans "$FAKE_GH/files.json" ;;
  "api repos/acme/svc/labels "*) ;;
  "api repos/acme/svc/issues/7/labels "*) echo '{}' ;;
  "api --method DELETE repos/acme/svc/issues/7/labels/"*) ;;
  "api --paginate repos/acme/svc/issues/7/comments "*) ans "$FAKE_GH/comments.json" ;;
  "api repos/acme/svc/issues/7/comments "*) last="${*: -1}"; cp "${last#body=@}" "$FAKE_GH/posted.md" ;;
  "api --method PATCH repos/acme/svc/issues/comments/"*) last="${*: -1}"; cp "${last#body=@}" "$FAKE_GH/patched.md"
                                                          echo "${4##*/}" > "$FAKE_GH/patched-id" ;;
  "api repos/acme/svc/rules/branches/main "*) ans "$FAKE_GH/rules.json" ;;
  "api --paginate repos/acme/svc/commits/"*"/check-runs "*) ans "$FAKE_GH/checks.json" ;;
  "pr merge 7 "*) [[ ! -f "$FAKE_GH/merge-fails" ]] || { echo "the base branch policy prohibits the merge" >&2; exit 1; }
                  touch "$FAKE_GH/merged" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
GH
cat > "$work/bin/agent" <<'AG'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FAKE_GH/agent-args"; pwd > "$FAKE_GH/agent-cwd"
# As the real CLI does: the value after --print that starts with "-" is read as an option, and the run fails.
# (An agent file begins with "---" front matter; the java-pipeline 0.21.0 review died on exactly that.)
[[ "${1:-}" == --print && "${2:-}" != -* ]] || { echo "error: unknown option '${2:0:20}'" >&2; exit 1; }
case "$SCENARIO" in
  approve)   text=$'Read the diff. Nothing to fix.\n\nVERDICT: APPROVE' ;;
  reject)    text=$'MUST FIX: a leak.\n\nVERDICT: REQUEST CHANGES' ;;
  midway)    text=$'VERDICT: APPROVE\nbut on second thought there is a problem' ;;
  noverdict) text='Looks fine to me.' ;;
  crash)     exit 3 ;;
esac
jq -n --arg r "$text" '{result: $r}'
AG
chmod +x "$work/bin/gh" "$work/bin/agent"
sha=1111111111111111111111111111111111111111 other=2222222222222222222222222222222222222222
export PATH="$work/bin:$PATH" FAKE_GH="$work/gh" GITHUB_REPOSITORY=acme/svc GH_TOKEN=t \
  FACTORY_STATE="$work/state" FACTORY_AGENT_CMD="$work/bin/agent" FACTORY_HANDOFF="$work/handoff"
unset GITHUB_STEP_SUMMARY GITHUB_OUTPUT FACTORY_PAUSED PR SHA TIER VERDICT LOW 2>/dev/null || true

# The reviewer's brief comes from the pinned plugin, fetched outside the PR checkout.
plugin="$work/plugin"; mkdir -p "$plugin/agents"
printf -- '---\nname: code-reviewer\n---\nReview the diff.\n' > "$plugin/agents/code-reviewer.md"
export FACTORY_PLUGIN_DIR="$plugin"

# A PR checkout with an origin/main, for the reviewer.
pr="$work/prdir"; export PR_DIR="$pr"
git init -q -b main "$pr"; g() { git -C "$pr" -c user.name=t -c user.email=t@example.invalid "$@"; }
echo a > "$pr/a.md"; g add a.md; g commit -qm base; g update-ref refs/remotes/origin/main HEAD
g switch -q -c topic; mkdir -p "$pr/src/main"; echo b > "$pr/src/main/B.java"; g add src; g commit -qm change
real_sha="$(g rev-parse HEAD)"

fresh() { # fresh <files...>: an open PR from a branch of this repo, green required checks, no comments yet
  rm -rf "$FAKE_GH" "$work/state" "$work/handoff"; mkdir -p "$FAKE_GH" "$work/handoff"; : > "$FAKE_GH/calls"
  jq -n --arg sha "$sha" --argjson n "$#" '{number:7, state:"open", draft:false, title:"docs: x", user:{login:"someone"},
    head:{sha:$sha, repo:{full_name:"acme/svc"}}, base:{ref:"main"}, labels:[], changed_files:$n}' > "$FAKE_GH/pr.json"
  printf '%s\n' "$@" | jq -R '{filename: .}' | jq -s . > "$FAKE_GH/files.json"
  echo '[{"number":7,"state":"open"}]' > "$FAKE_GH/commit-pulls.json"
  echo '[]' > "$FAKE_GH/comments.json"
  echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"verify"},{"context":"manifests"}]}}]' > "$FAKE_GH/rules.json"
  checks '"verify","2026-01-01T00:00:00Z","success"' '"manifests","2026-01-01T00:00:00Z","success"'
}
checks() { printf '%s\n' "$@" | jq -R '"[" + . + "]" | fromjson | {name: .[0], started_at: .[1], conclusion: .[2]}' | jq -s '{check_runs: .}' > "$FAKE_GH/checks.json"; }
setpr() { jq "$1" "$FAKE_GH/pr.json" > "$FAKE_GH/pr.tmp" && mv "$FAKE_GH/pr.tmp" "$FAKE_GH/pr.json"; }
merged() { [[ -f "$FAKE_GH/merged" ]]; }
outputs() { : > "$work/out"; export GITHUB_OUTPUT="$work/out"; }
out_is() { grep -qx "$1" "$work/out"; }

# --- label
fresh docs/a.md; PR=7 rt label >/dev/null && grep -q 'issues/7/labels -f labels\[\]=risk:low' "$FAKE_GH/calls" && ok "label: a docs PR gets risk:low" || bad "label: no risk:low"
fresh src/main/A.java; setpr '.labels=[{name:"risk:low"}]'; PR=7 rt label >/dev/null
grep -q 'labels\[\]=risk:high' "$FAKE_GH/calls" && grep -q 'DELETE.*labels/risk:low' "$FAKE_GH/calls" && ok "label: a code PR gets risk:high and loses risk:low" || bad "label: high not set or low kept"
fresh docs/a.md; setpr '.labels=[{name:"risk:high"}]'; PR=7 rt label >/dev/null
! grep -q 'labels\[\]=risk:low' "$FAKE_GH/calls" && ok "label: risk:high stays sticky" || bad "label: replaced risk:high"
fresh docs/a.md; setpr '.changed_files=5'; PR=7 rt label >/dev/null
grep -q 'labels\[\]=risk:high' "$FAKE_GH/calls" && ok "label: files GitHub counted but did not list -> high" || bad "label: trusted a partial file list"

# --- pick: every PR from a branch of the repo is reviewed; only a low one may merge
outputs; fresh src/main/A.java; HEAD_SHA="$sha" rt pick >/dev/null
out_is review=true && out_is low=false && out_is pr=7 && out_is "sha=$sha" && out_is tier=high \
  && ok "pick: a feature PR (high) is reviewed and may not merge" || bad "pick high: $(tr '\n' ' ' < "$work/out")"
outputs; fresh docs/a.md; HEAD_SHA="$sha" rt pick >/dev/null
out_is review=true && out_is low=true && out_is tier=low && ok "pick: a docs PR is reviewed and may merge" || bad "pick low: $(tr '\n' ' ' < "$work/out")"
outputs; fresh docs/a.md; PR=7 rt pick >/dev/null; out_is review=true && out_is pr=7 && ok "pick: by hand with a PR number" || bad "pick by hand: $(tr '\n' ' ' < "$work/out")"
outputs; fresh docs/a.md; setpr '.labels=[{name:"risk:high"}]'; PR=7 rt pick >/dev/null
out_is review=true && out_is low=false && ok "pick: a risk:high label stops the merge, not the review" || bad "pick label: $(tr '\n' ' ' < "$work/out")"
for c in '.state="closed"|closed' '.draft=true|a draft' '.head.repo.full_name="evil/fork"|a fork (the review holds the Claude credential)' '.base.ref="release"|another base'; do
  outputs; fresh docs/a.md; setpr "${c%%|*}"; PR=7 rt pick >/dev/null
  out_is review=false && out_is low=false && ok "pick: no review for ${c##*|}" || bad "pick: reviewed ${c##*|}"
done
outputs; fresh docs/a.md; echo '[]' > "$FAKE_GH/commit-pulls.json"; HEAD_SHA="$sha" rt pick >/dev/null
out_is review=false && ok "pick: a CI run with no open PR reviews nothing" || bad "pick: no PR: $(tr '\n' ' ' < "$work/out")"
outputs; fresh docs/a.md; FACTORY_PAUSED=true PR=7 rt pick >/dev/null
out_is review=false && ok "pick: paused reviews nothing" || bad "pick: reviewed while paused"
unset GITHUB_OUTPUT

# --- review
review() { PR=7 SHA="$real_sha" TIER="${TIER:-high}" SCENARIO="$1" rt review > "$work/rout" 2>&1; }
for s in approve:approve reject:reject midway:none noverdict:none; do
  outputs; fresh src/main/A.java
  review "${s%%:*}" && out_is "verdict=${s##*:}" && ok "review: '${s%%:*}' -> ${s##*:}" || bad "review ${s%%:*}: $(cat "$work/out") $(tail -n 2 "$work/rout")"
done
unset GITHUB_OUTPUT
fresh src/main/A.java; review crash && bad "review: a crashed reviewer passed" || ok "review: a crashed reviewer fails the job"
fresh src/main/A.java; PR=7 SHA="$other" TIER=high SCENARIO=approve rt review >/dev/null 2>&1 && bad "review: reviewed another commit" || ok "review: the checkout must be the sha asked for"
fresh src/main/A.java; review approve
args="$(cat "$FAKE_GH/agent-args")"
[[ "$args" == *'--allowedTools Read Grep Glob'* && "$args" != *bypassPermissions* ]] && ok "review: read-only tools, no bypass" || bad "review: tools not read-only: $args"
[[ "$args" == *"Review the diff."* && "$args" != *"name: code-reviewer"* && "$args" == *"VERDICT: APPROVE"* ]] && ok "review: the pinned plugin's code-reviewer brief and the verdict line are in the prompt" || bad "review: prompt incomplete"
[[ "$args" == *"risk:high"* && "$args" == *"production code"* ]] && ok "review: a high PR's prompt says it is not limited to docs and tests" || bad "review: prompt for a high PR: $args"
cwd="$(cat "$FAKE_GH/agent-cwd")"
[[ "$cwd" != "$pr"* && -z "$(ls -A "$cwd")" ]] && ok "review: starts in an empty directory, not the PR checkout" || bad "review: wrong cwd $cwd"
[[ "$args" == *"--add-dir $pr --setting-sources user --strict-mcp-config"* ]] && ok "review: the checkout is data only (no project settings, hooks or MCP)" || bad "review: the PR's settings could load: $args"
grep -q 'factory-review' "$work/state/review.md" && grep -q "${real_sha:0:12}" "$work/state/review.md" && grep -q 'advisory' "$work/state/review.md" \
  && ok "review: review.md carries the marker, the sha and says it is advisory" || bad "review: review.md: $(head -3 "$work/state/review.md")"
mv "$plugin/agents/code-reviewer.md" "$work/brief.bak"; fresh src/main/A.java
review approve && bad "review: ran without the plugin's brief" || ok "review: no code-reviewer brief, no review"
mv "$work/brief.bak" "$plugin/agents/code-reviewer.md"
env -u FACTORY_AGENT_CMD -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY PR=7 SHA="$real_sha" TIER=high "$script" review >/dev/null 2>&1 \
  && bad "review: ran with no credential" || ok "review: no credential, no run"
outputs; fresh src/main/A.java
big="$work/bigpr"; git clone -q "$pr" "$big"; git -C "$big" update-ref refs/remotes/origin/main "$(git -C "$pr" rev-parse main)"
for i in $(seq 9000); do echo "line $i of a very long generated file that makes the diff big"; done > "$big/docs-big.md"
git -C "$big" add docs-big.md; git -C "$big" -c user.name=t -c user.email=t@example.invalid commit -qm big
PR_DIR="$big" PR=7 SHA="$(git -C "$big" rev-parse HEAD)" TIER=high SCENARIO=approve rt review >/dev/null 2>&1 || true
out_is verdict=skipped && [[ ! -f "$FAKE_GH/agent-args" ]] && [[ ! -f "$work/state/review.md" ]] && ok "review: a diff over 400 kB is not reviewed (skipped, nothing to post)" || bad "review: reviewed a huge diff"
unset GITHUB_OUTPUT

# --- comment: one per PR, replaced on a new head
comment() { PR=7 rt comment > "$work/cout" 2>&1; }
fresh src/main/A.java; printf '<!-- factory-review -->\nreview one\n' > "$work/handoff/review.md"
comment && [[ -s "$FAKE_GH/posted.md" && ! -f "$FAKE_GH/patched.md" ]] && ok "comment: the first review is a new comment" || bad "comment: first: $(cat "$work/cout")"
fresh src/main/A.java; printf '<!-- factory-review -->\nreview two\n' > "$work/handoff/review.md"
echo '[{"id":11,"user":{"login":"someone"},"body":"<!-- factory-review --> forged"},{"id":42,"user":{"login":"github-actions[bot]"},"body":"<!-- factory-review -->\nreview one"}]' > "$FAKE_GH/comments.json"
comment && [[ "$(cat "$FAKE_GH/patched-id" 2>/dev/null)" == 42 && ! -f "$FAKE_GH/posted.md" ]] \
  && ok "comment: a new head replaces the bot's earlier review, not someone else's comment" || bad "comment: replace: $(cat "$work/cout") id=$(cat "$FAKE_GH/patched-id" 2>/dev/null)"
fresh src/main/A.java; comment && bad "comment: posted with no review" || ok "comment: no review.md, no comment"

# --- merge: only low, approve, same sha, green required checks
domerge() { PR=7 SHA="$sha" VERDICT="${VERDICT:-approve}" rt merge > "$work/mout" 2>&1; }
held() { # held <description> <text in the reason>
  if ! domerge; then bad "merge: $1 failed: $(tail -n 2 "$work/mout")"
  elif merged; then bad "merge: $1 but it merged"
  elif grep -qF -- "$2" "$work/mout"; then ok "merge: $1"
  else bad "merge: $1, wrong reason: $(tail -n 2 "$work/mout")"; fi
}
fresh docs/a.md; domerge && merged && grep -q -- "--match-head-commit $sha" "$FAKE_GH/calls" && ok "merge: low + green + approve merges at the reviewed sha" || bad "merge: did not merge: $(tail -n 2 "$work/mout")"
fresh src/main/A.java; held "a feature PR (high), even with APPROVE" "risk:high"
fresh docs/a.md; VERDICT=reject held "a reject verdict" "verdict is 'reject'"
fresh docs/a.md; VERDICT=none held "no verdict" "verdict is 'none'"
fresh docs/a.md; FACTORY_PAUSED=true held "paused" "paused"
fresh docs/a.md; setpr ".head.sha=\"$other\""; held "the branch moved after the review" "moved"
fresh docs/a.md; setpr '.labels=[{name:"risk:high"}]'; held "a risk:high label" "risk:high"
fresh docs/a.md; setpr '.head.repo.full_name="evil/fork"'; held "a fork" "another repository"
fresh docs/a.md; checks '"verify","2026-01-01T00:00:00Z","success"'; held "a required check missing" "'manifests' is 'missing'"
fresh docs/a.md; checks '"verify","2026-01-01T00:00:00Z","success"' '"manifests","2026-01-01T00:00:00Z","failure"'; held "a required check red" "'manifests' is 'failure'"
fresh docs/a.md; echo '[]' > "$FAKE_GH/rules.json"; domerge && bad "merge: merged with no required checks" || { merged && bad "merge: merged with no required checks" || ok "merge: refuses when main has no required checks"; }
fresh docs/a.md; touch "$FAKE_GH/merge-fails"; held "GitHub refuses (branch behind)" "GitHub refused"

# --- the workflows
wf="$t/.github/workflows/factory-review.yml" lw="$t/.github/workflows/risk-tier.yml"
[[ -f "$wf" && -f "$lw" ]] && ok "both workflows exist" || bad "missing factory-review.yml or risk-tier.yml"
job() { awk -v j="$1" '$0 ~ "^  "j":$"{on=1; next} /^  [a-z][a-z-]*:$/{on=0} on' "$wf"; }
grep -q 'pull_request_target' "$lw" && grep -q 'ref: ${{ github.event.repository.default_branch }}' "$lw" && ! grep -q 'github.event.pull_request.head' "$lw" \
  && ok "risk-tier.yml labels from main's code, never the PR's" || bad "risk-tier.yml checks out the PR"
grep -qE 'workflows: \[CI\]' "$wf" && ok "factory-review.yml runs when CI finishes" || bad "factory-review.yml is not triggered by CI"
grep -q "verdict != 'skipped'" <<<"$(job comment)" && ok "comment job: nothing to post for a skipped review" || bad "comment job runs for a skipped review"
grep -qx 'name: CI' "$t/.github/workflows/ci.yml" && ok "the template's CI workflow is named CI" || bad "ci.yml is not named CI: the review would never start"
body="$(job review)"
grep -q 'CLAUDE_CODE_OAUTH_TOKEN' <<<"$body" && ! grep -qE 'GH_TOKEN|github\.token|FACTORY_APP|: write' <<<"$body" \
  && ok "review job: the Claude credential, no GitHub token, nothing writable" || bad "review job holds a GitHub token or write permission"
grep -q 'ref: ${{ github.event.repository.default_branch }}' <<<"$body" && grep -q 'path: pr' <<<"$body" \
  && ok "review job: trusted scripts from main, the PR head as data in pr/" || bad "review job checkouts"
body="$(job pick)"; ! grep -qE 'secrets\.|: write' <<<"$body" && ok "pick job: no secrets, nothing writable" || bad "pick job holds secrets or write"
body="$(job comment)"; grep -q 'pull-requests: write' <<<"$body" && ! grep -qE 'secrets\.' <<<"$body" && ok "comment job: the workflow token only" || bad "comment job"
body="$(job merge)"; grep -q "needs.pick.outputs.low == 'true'" <<<"$body" && grep -q "needs.review.outputs.verdict == 'approve'" <<<"$body" \
  && ok "merge job: only a low PR with an APPROVE" || bad "merge job condition"
! grep -qE '^\s+run:.*\$\{\{' "$wf" "$lw" && ok "no run command interpolates an expression" || bad "a run command interpolates an expression"

[[ $fails -eq 0 ]] && echo "service review tests ($(basename "$t")): OK" || echo "service review tests ($(basename "$t")): FAILED"
exit $fails
