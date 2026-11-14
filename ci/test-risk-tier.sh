#!/usr/bin/env bash
# Tests .github/scripts/risk-tier.sh (factory ADR 0027) without GitHub or Claude: `gh` is a fake that answers from
# fixture files and records its calls; the reviewer is a stand-in that prints the verdict the scenario names.
#   ci/test-risk-tier.sh        (from the repo root)
set -euo pipefail

[[ -x .github/scripts/risk-tier.sh ]] || { echo "run from the repo root" >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/risk-tier-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }
script="$PWD/.github/scripts/risk-tier.sh"
rt() { "$script" "$@"; }

# --- classify: every path class -------------------------------------------------------------------------------
tier() { # tier <author> <title> <paths...> -> the first output line
  local a="$1" t="$2" out; shift 2
  # Not `rt classify | head -n 1`: head leaves after the tier, and the reasons still being written then kill
  # classify with SIGPIPE (exit 141 under pipefail), now and then.
  out="$(printf '%s\n' "$@" | PR_AUTHOR="$a" PR_TITLE="$t" rt classify)"
  head -n 1 <<<"$out"
}
expect() { # expect <low|high> <description> <author> <title> <paths...>
  local want="$1" what="$2" a="$3" t="$4"; shift 4
  local got; got="$(tier "$a" "$t" "$@")"
  [[ "$got" == "$want" ]] && ok "$what -> $want" || bad "$what: wanted $want, got $got"
}
dep='dependabot[bot]'
expect low  "docs only"                      me "docs" docs/ONBOARDING.md README.md docs/plans/b6.md
expect low  "an ordinary ADR"                me "adr" docs/factory-adr/0015-releases-and-pinned-plugin.md
expect low  "plugin readme and changelog"    me "docs" plugins/java-pipeline/README.md plugins/java-pipeline/CHANGELOG.md
expect low  "test sources only"              me "tests" plugins/java-pipeline/templates/skeleton/src/test/java/com/x/FooTest.java
expect high "an ADR that sets rules (0020)"  me "adr" docs/factory-adr/0020-self-running-factory.md
expect high "the new tier ADR"               me "adr" docs/factory-adr/0027-risk-tiers-and-auto-merge.md
expect high "the roadmap (steers agents)"    me "docs" docs/ROADMAP.md
expect high "CLAUDE.md"                      me "docs" CLAUDE.md
expect high "a workflow"                     me "ci" .github/workflows/ci.yml
expect high "a template's workflow"          me "ci" plugins/java-pipeline/templates/skeleton/.github/workflows/ci.yml
expect high "a pom.xml"                      me "deps" plugins/java-pipeline/templates/skeleton/pom.xml
expect high "factory-parent"                 me "deps" parents/factory-parent/pom.xml
expect high "deploy/"                        me "deploy" plugins/java-pipeline/templates/skeleton/deploy/k8s/base/deployment.yaml
expect high "a migration"                    me "db" plugins/java-pipeline/templates/payments-example/src/main/resources/db/migration/V2__x.sql
expect high "security code"                  me "sec" plugins/java-pipeline/templates/skeleton/src/main/java/com/x/security/Foo.java
expect high "a test of auth code"            me "tests" plugins/java-pipeline/templates/skeleton/src/test/java/com/x/AuthFilterTest.java
expect high "money code"                     me "money" plugins/java-pipeline/templates/payments-example/src/main/java/com/x/Money.java
expect high "idempotency code"               me "idem" plugins/java-pipeline/templates/payments-example/src/main/java/com/x/IdempotencyStore.java
expect high "ArchitectureTest"               me "tests" plugins/java-pipeline/templates/skeleton/src/test/java/com/x/ArchitectureTest.java
expect high ".claude/"                       me "agents" .claude/settings.json
expect high "the classifier script"          me "ci" .github/scripts/risk-tier.sh
expect high "the classifier workflow"        me "ci" .github/workflows/risk-tier.yml
expect high "the auto-merge workflow"        me "ci" .github/workflows/auto-merge.yml
expect high "the classifier's test"          me "ci" ci/test-risk-tier.sh
expect high "a path nobody listed"           me "misc" scripts/new-thing.sh
expect high "a main source file"             me "feat" plugins/java-pipeline/templates/skeleton/src/main/java/com/x/Greeting.java
expect high "low and high mixed"             me "mixed" docs/ONBOARDING.md .github/workflows/ci.yml
expect high "no files at all"                me "empty"
# Dependabot: only a patch/minor bump of a dependency file is low.
expect low  "dependabot minor, pom.xml"      "$dep" "build(deps): bump org.foo:bar from 1.2.0 to 1.3.0" plugins/java-pipeline/templates/skeleton/pom.xml
expect low  "dependabot patch, action pin"   "$dep" "ci: bump actions/checkout from 7.0.0 to 7.0.1" .github/workflows/ci.yml plugins/java-pipeline/templates/skeleton/.github/workflows/ci.yml
expect high "dependabot major"               "$dep" "build(deps): bump org.foo:bar from 1.9.0 to 2.0.0" plugins/java-pipeline/templates/skeleton/pom.xml
expect high "dependabot group (no versions)" "$dep" "build(deps): bump the maven group with 3 updates" plugins/java-pipeline/templates/skeleton/pom.xml
expect high "dependabot bumping the parent"  "$dep" "build(deps): bump org.foo:bar from 1.2.0 to 1.3.0" parents/factory-parent/pom.xml
expect high "dependabot touching the classifier" "$dep" "ci: bump actions/checkout from 7.0.0 to 7.0.1" .github/workflows/auto-merge.yml
expect high "dependabot plus an unlisted file" "$dep" "build(deps): bump org.foo:bar from 1.2.0 to 1.3.0" plugins/java-pipeline/templates/skeleton/pom.xml scripts/x.sh
expect high "a person's bump title is no Dependabot" me "build(deps): bump org.foo:bar from 1.2.0 to 1.3.0" plugins/java-pipeline/templates/skeleton/pom.xml

# --- the pull request side, with a fake gh -------------------------------------------------------------------
mkdir -p "$work/bin" "$work/gh"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH/calls"
expr="" args=("$@") i=0
while (( i < ${#args[@]} )); do [[ "${args[i]}" == --jq ]] && expr="${args[i+1]}"; i=$((i+1)); done
ans() { if [[ -n "$expr" ]]; then jq -r "$expr" "$1"; else cat "$1"; fi; }
case "$*" in
  "api repos/acme/factory/pulls/7") cat "$FAKE_GH/pr.json" ;;
  "api --paginate repos/acme/factory/pulls/7/files "*) ans "$FAKE_GH/files.json" ;;
  "api repos/acme/factory/labels "*) [[ ! -f "$FAKE_GH/label-exists" ]] || exit 1 ;;
  "api repos/acme/factory/issues/7/labels "*) echo '{}' ;;
  "api --method DELETE repos/acme/factory/issues/7/labels/"*) ;;
  "api repos/acme/factory/rules/branches/main "*) ans "$FAKE_GH/rules.json" ;;
  "api --paginate repos/acme/factory/commits/"*"/check-runs "*) ans "$FAKE_GH/checks.json" ;;
  "api repos/acme/factory/issues/7/comments "*) last="${@: -1}"; cp "${last#body=@}" "$FAKE_GH/comment.md" ;;
  "pr merge 7 "*) [[ ! -f "$FAKE_GH/merge-fails" ]] || { echo "Pull request is not mergeable: the base branch policy prohibits the merge" >&2; exit 1; }
                  touch "$FAKE_GH/merged" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
GH
cat > "$work/bin/agent" <<'AG'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FAKE_GH/agent-args"; pwd > "$FAKE_GH/agent-cwd"
case "$SCENARIO" in
  approve)  text=$'Read the diff. Nothing to fix.\n\nVERDICT: APPROVE' ;;
  reject)   text=$'MUST FIX: a broken link.\n\nVERDICT: REQUEST CHANGES' ;;
  midway)   text=$'VERDICT: APPROVE\nbut on second thought there is a problem' ;;
  noverdict) text='Looks fine to me.' ;;
  crash)    exit 3 ;;
esac
jq -n --arg r "$text" '{result: $r}'
AG
chmod +x "$work/bin/gh" "$work/bin/agent"
sha=1111111111111111111111111111111111111111 other=2222222222222222222222222222222222222222
export PATH="$work/bin:$PATH" FAKE_GH="$work/gh" GITHUB_REPOSITORY=acme/factory GH_TOKEN=t PR=7 SHA="$sha" \
  FACTORY_STATE="$work/state" FACTORY_AGENT_CMD="$work/bin/agent" FACTORY_HANDOFF="$work/handoff"
unset GITHUB_STEP_SUMMARY GITHUB_OUTPUT FACTORY_PAUSED 2>/dev/null || true

# a PR checkout with an origin/main, for the reviewer
pr="$work/prdir"; export PR_DIR="$pr"
git init -q -b main "$pr"; g() { git -C "$pr" -c user.name=t -c user.email=t@example.invalid "$@"; }
echo a > "$pr/a.md"; g add a.md; g commit -qm base; g update-ref refs/remotes/origin/main HEAD
g switch -q -c topic; echo b > "$pr/b.md"; g add b.md; g commit -qm change; real_sha="$(g rev-parse HEAD)"

fresh() { # fresh <files...>: an open low PR from this repo with green checks
  rm -rf "$FAKE_GH" "$work/state" "$work/handoff"; mkdir -p "$FAKE_GH" "$work/handoff"; : > "$FAKE_GH/calls"
  jq -n --arg sha "${HEAD_SHA:-$sha}" --argjson n "$#" '{state:"open", draft:false, title:"docs: x", user:{login:"someone"},
    head:{sha:$sha, repo:{full_name:"acme/factory"}}, base:{ref:"main"}, labels:[], changed_files:$n}' > "$FAKE_GH/pr.json"
  printf '%s\n' "$@" | jq -R '{filename: .}' | jq -s . > "$FAKE_GH/files.json"
  echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"build"},{"context":"manifests"}]}}]' > "$FAKE_GH/rules.json"
  checks '"build","2026-01-01T00:00:00Z","success"' '"manifests","2026-01-01T00:00:00Z","success"'
}
checks() { printf '%s\n' "$@" | jq -R '"[" + . + "]" | fromjson | {name: .[0], started_at: .[1], conclusion: .[2]}' | jq -s '{check_runs: .}' > "$FAKE_GH/checks.json"; }
setpr() { jq "$1" "$FAKE_GH/pr.json" > "$FAKE_GH/pr.tmp" && mv "$FAKE_GH/pr.tmp" "$FAKE_GH/pr.json"; }
merged() { [[ -f "$FAKE_GH/merged" ]]; }
outputs() { : > "$work/out"; export GITHUB_OUTPUT="$work/out"; }

# label
fresh docs/a.md; rt label >/dev/null && grep -q 'issues/7/labels -f labels\[\]=risk:low' "$FAKE_GH/calls" && ok "label: a docs PR gets risk:low" || bad "label: no risk:low"
fresh .github/workflows/ci.yml; setpr '.labels=[{name:"risk:low"}]'; rt label >/dev/null
grep -q 'labels\[\]=risk:high' "$FAKE_GH/calls" && grep -q 'DELETE.*labels/risk:low' "$FAKE_GH/calls" && ok "label: a workflow PR gets risk:high and loses risk:low" || bad "label: high not set / low kept"
fresh docs/a.md; setpr '.labels=[{name:"risk:high"}]'; rt label >/dev/null
! grep -q 'labels\[\]=risk:low' "$FAKE_GH/calls" && ok "label: risk:high stays sticky" || bad "label: replaced risk:high"
fresh docs/a.md; setpr '.changed_files=5'; rt label >/dev/null
grep -q 'labels\[\]=risk:high' "$FAKE_GH/calls" && ok "label: files GitHub counted but did not list -> high" || bad "label: trusted a partial file list"

# eligible
outputs
fresh docs/a.md; rt eligible >/dev/null; grep -qx 'eligible=true' "$work/out" && grep -qx "sha=$sha" "$work/out" && ok "eligible: open low PR" || bad "eligible: $(cat "$work/out")"
for c in '.state="closed"|closed' '.draft=true|draft' '.head.repo.full_name="evil/fork"|fork' '.base.ref="release"|other base' '.labels=[{name:"risk:high"}]|risk:high label'; do
  outputs; fresh docs/a.md; setpr "${c%%|*}"; rt eligible >/dev/null
  grep -qx 'eligible=false' "$work/out" && ok "eligible: refuses ${c##*|}" || bad "eligible: accepted ${c##*|}"
done
outputs; fresh src/main/Foo.java; rt eligible >/dev/null; grep -qx 'eligible=false' "$work/out" && ok "eligible: refuses a high PR" || bad "eligible: accepted a high PR"
unset GITHUB_OUTPUT

# review
review() { SHA="$real_sha" SCENARIO="$1" rt review > "$work/rout" 2>&1; }
verdict_is() { grep -qx "verdict=$1" "$work/out"; }
for s in approve:approve reject:reject midway:none noverdict:none; do
  outputs; fresh docs/a.md
  review "${s%%:*}" && verdict_is "${s##*:}" && ok "review: '${s%%:*}' -> ${s##*:}" || bad "review ${s%%:*}: $(cat "$work/out") $(tail -n 2 "$work/rout")"
done
unset GITHUB_OUTPUT
fresh docs/a.md; review crash && bad "review: a crashed reviewer passed" || ok "review: a crashed reviewer fails the job"
fresh docs/a.md; SHA="$other" SCENARIO=approve rt review >/dev/null 2>&1 && bad "review: reviewed a different commit than asked" || ok "review: the checkout must be the sha asked for"
fresh docs/a.md; review approve
args="$(cat "$FAKE_GH/agent-args")"
[[ "$args" == *'--allowedTools Read Grep Glob'* && "$args" != *bypassPermissions* ]] && ok "review: read-only tools, no bypass" || bad "review: tools are not read-only: $args"
[[ "$args" == *"name: code-reviewer"* && "$args" == *"VERDICT: APPROVE"* ]] && ok "review: the code-reviewer brief and the verdict line are in the prompt" || bad "review: prompt incomplete"
cwd="$(cat "$FAKE_GH/agent-cwd")"
[[ "$cwd" != "$pr"* && -z "$(ls -A "$cwd")" ]] && ok "review: starts in an empty directory, not the PR checkout" || bad "review: wrong cwd $cwd"
[[ "$args" == *"--add-dir $pr --setting-sources user --strict-mcp-config"* ]] && ok "review: the checkout is data only (no project settings, hooks or MCP servers)" || bad "review: the PR's settings could load: $args"
grep -q 'APPROVE' "$work/state/review.md" && ok "review: review.md written" || bad "review: no review.md"
env -u FACTORY_AGENT_CMD -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY SHA="$real_sha" "$script" review >/dev/null 2>&1 && bad "review: ran with no credential" || ok "review: no credential, no run"

# merge
domerge() { VERDICT="${VERDICT:-approve}" rt merge > "$work/mout" 2>&1; }
held() { # held <description> <text in the reason>
  if ! domerge; then bad "merge: $1 failed: $(tail -n 2 "$work/mout")"
  elif merged; then bad "merge: $1 but it merged"
  elif grep -qF -- "$2" "$work/mout"; then ok "merge: $1"
  else bad "merge: $1, wrong reason: $(tail -n 2 "$work/mout")"; fi
}
fresh docs/a.md; domerge && merged && grep -q -- "--match-head-commit $sha" "$FAKE_GH/calls" && grep -q -- '--merge' "$FAKE_GH/calls" && ok "merge: low + green + approve merges at the reviewed sha" || bad "merge: did not merge: $(tail -n 2 "$work/mout")"
fresh docs/a.md; echo '**review**' > "$work/handoff/review.md"; domerge; [[ -s "$FAKE_GH/comment.md" ]] && ok "merge: the review is posted on the PR" || bad "merge: no review comment"
fresh docs/a.md; VERDICT=reject held "a reject verdict" "verdict is 'reject'"
fresh docs/a.md; VERDICT=none held "no verdict" "verdict is 'none'"
fresh docs/a.md; FACTORY_PAUSED=true held "paused" "paused"
fresh docs/a.md; setpr ".head.sha=\"$other\""; held "the branch moved after the review" "moved"
fresh .github/workflows/ci.yml; held "the PR became high after the review" "risk:high"
fresh docs/a.md; setpr '.labels=[{name:"risk:high"}]'; held "a risk:high label" "risk:high"
fresh docs/a.md; setpr '.draft=true'; held "a draft" "draft"
fresh docs/a.md; checks '"build","2026-01-01T00:00:00Z","success"'; held "a required check missing" "'manifests' is 'missing'"
fresh docs/a.md; checks '"build","2026-01-01T00:00:00Z","success"' '"manifests","2026-01-01T00:00:00Z","failure"'; held "a required check red" "'manifests' is 'failure'"
fresh docs/a.md; checks '"build","2026-01-01T00:00:00Z","success"' '"manifests","2026-01-01T00:00:00Z","none"'; held "a required check still running" "'manifests' is 'none'"
fresh docs/a.md; checks '"build","2026-01-01T00:00:00Z","success"' '"manifests","2026-01-01T00:00:00Z","failure"' '"manifests","2026-01-02T00:00:00Z","success"'
domerge && merged && ok "merge: a re-run that passed counts (latest run wins)" || bad "merge: ignored the re-run"
fresh docs/a.md; checks '"build","2026-01-01T00:00:00Z","success"' '"manifests","2026-01-02T00:00:00Z","failure"' '"manifests","2026-01-01T00:00:00Z","success"'
held "the latest run failed after an earlier pass" "'manifests' is 'failure'"
fresh docs/a.md; checks '"other","2026-01-01T00:00:00Z","success"'; held "only unrelated checks are green" "'build' is 'missing'"
fresh docs/a.md; echo '[]' > "$FAKE_GH/rules.json"; domerge && bad "merge: merged with no required checks configured" || { merged && bad "merged" || ok "merge: refuses when main has no required checks"; }
fresh docs/a.md; touch "$FAKE_GH/merge-fails"; held "GitHub refuses (branch behind)" "GitHub refused"

# the workflows and the classifier agree on what is protected
grep -q 'risk-tier\.sh' .github/workflows/risk-tier.yml && grep -q 'risk-tier\.sh' .github/workflows/auto-merge.yml && ok "workflows call the script" || bad "workflows do not call the script"
grep -qF '2[0-467]' .github/scripts/factory-step.sh && ok "factory-step's protected list includes ADR 0027" || bad "factory-step's protected list lacks ADR 0027"

exit $fails
