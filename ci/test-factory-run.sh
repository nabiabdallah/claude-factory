#!/usr/bin/env bash
# Tests a project's .github/scripts/factory-run.sh (factory ADRs 0018 and 0019) on a throwaway copy, without GitHub, Maven
# or a Claude credential: `gh` is a fake that records its calls, the agent is a stand-in that makes the commits a
# scenario asks for, and `./mvnw verify` is replaced by a command that passes or fails. The jobs of the workflow
# (claude-factory ADR 0023) run in separate clones, handing over only the bundle and the report: the agent job in
# the project copy, the gate job (q:) and the publish job (r:) in fresh clones of the base commit.
#   ci/test-factory-run.sh <project-dir>     (a generated project or a template directory)
set -euo pipefail

[[ $# -eq 1 && -x "$1/.github/scripts/factory-run.sh" ]] || { echo "usage: $0 <project-dir with .github/scripts/factory-run.sh>" >&2; exit 2; }

work="$(mktemp -d "${TMPDIR:-/tmp}/factory-run-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp -r "$1" "$work/p"
cd "$work/p"
rm -rf target .git
arch="$(find src/test/java -name ArchitectureTest.java | head -n 1)"
some_test="$(find src/test/java -name '*Test.java' ! -name ArchitectureTest.java | head -n 1)"
[[ -n "$arch" && -n "$some_test" ]] || { echo "$1 has no ArchitectureTest and another test" >&2; exit 2; }

# The project as new-project leaves it: pinned to a plugin release. Plus one approved and one draft spec.
python3 -I - <<'PY'
import json
p = ".claude/settings.json"
s = json.load(open(p))
s["extraKnownMarketplaces"]["claude-factory"]["source"]["ref"] = "java-pipeline-v9.9.9"
open(p, "w").write(json.dumps(s, indent=2) + "\n")
PY
spec() { # spec <file> <status line> <criteria>
  printf '# Spec: Greet a customer\n\n- Status: %s\n- Owner: test\n\n## Acceptance criteria\n%s\n\n## Failure modes\nnone\n' "$2" "$3" > "docs/specs/$1"
}
spec 0001-greet.md "Approved" "1. Given a name, when greeted, then the name is in the answer."
spec 0002-draft.md "Draft" "1. Given x, when y, then z."
spec 0003-template-status.md "Draft | Approved" "1. Given x, when y, then z."
spec 0004-no-criteria.md "Approved" "To be written."

git init -q -b main
g() { git -c user.name=test -c user.email=test@example.invalid "$@"; }
git add -A && g commit -q -m "project"
c0="$(git rev-parse HEAD)"
git init -q --bare "$work/remote.git"
git clone -q --bare "$work/p" "$work/base.git"

# Fake gh: answers from files in $FAKE_GH, appends every call to $FAKE_GH/calls.
mkdir -p "$work/bin" "$work/gh"
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH/calls"
case "$*" in # chaining (ADR 0026): dispatches, the issue itself, its labels, the pull request of a commit
  *"/actions/workflows/ci.yml/dispatches "*) [[ ! -f "$FAKE_GH/ci-refused" ]] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; exit 0 ;;
  *"/actions/workflows/factory-feature.yml/dispatches "*) [[ ! -f "$FAKE_GH/dispatch-refused" ]] || exit 1; exit 0 ;;
  *"/commits/"*"/pulls") cat "$FAKE_GH/pulls.json" 2>/dev/null || echo '[]'; exit 0 ;;
  *"/issues/5/labels "*) exit 0 ;;
  "api repos/acme/demo/issues/5") cat "$FAKE_GH/issue.json" 2>/dev/null || exit 1; exit 0 ;;
esac
case "$2" in
  */collaborators/*/permission) cat "$FAKE_GH/permission" ;;
  */branches/*) [[ -f "$FAKE_GH/branch-exists" ]] && echo branch || exit 1 ;;
  */pulls) [[ -f "$FAKE_GH/pr-refused" ]] && { echo "gh: GitHub Actions is not permitted to create or approve pull requests. (HTTP 403)" >&2; exit 1; }
           echo "https://github.com/acme/demo/pull/7" ;;
  */comments\?*) cat "$FAKE_GH/comments.json" 2>/dev/null || echo '[]' ;;
  */comments) echo "https://github.com/acme/demo/issues/5#c" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
SH
# Stand-in agent: does what $SCENARIO says on the branch the runner created, the way the real agent would.
cat > "$work/bin/agent" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" > "$FAKE_GH/agent-args"
[[ "${FACTORY_HEADLESS:-}" == 1 ]] || { echo "FACTORY_HEADLESS not set" >&2; exit 3; }
g() { git -c user.name=agent -c user.email=agent@example.invalid "$@"; }
report=1; commit=1
new_spec() { # new_spec <file> <status> <open questions>   a complete spec, as the intake skill would write it
  sed -e 's/^# Spec: .*/# Spec: Farewell a customer/' -e "s/^- Status: .*/- Status: $2/" \
    -e 's/^1\. Given \.\.\..*/1. Given a name, when dismissed, then the name is in the answer./' docs/specs/_template.md \
    | sed '/^## Open questions/,$d' > "$1"
  printf '## Open questions\n%s\n' "$3" >> "$1"
}
case "$SCENARIO" in
  spec-*) grep -q 'factory-run-test idea marker' "$FACTORY_IDEA" || { echo "idea file missing" >&2; exit 4; } ;;
  *) mkdir -p src/main/java/demo; echo "class Greeter {}" > src/main/java/demo/Greeter.java ;;
esac
case "$SCENARIO" in
  spec-draft) new_spec docs/specs/0005-farewell.md Draft "- Should it be polite? Recommended: yes." ;;
  spec-approved) new_spec docs/specs/0005-farewell.md Approved "- none" ;;
  spec-approved-with-questions) new_spec docs/specs/0005-farewell.md Approved "- Should it be polite? Recommended: yes." ;;
  spec-no-status) new_spec docs/specs/0005-farewell.md "Draft | Approved" "- none" ;;
  spec-bad-name) new_spec "docs/specs/farewell.md" Draft "- none" ;;
  spec-missing-section) new_spec docs/specs/0005-farewell.md Draft "- none"; sed -i '/^## Authorization/d' docs/specs/0005-farewell.md ;;
  spec-no-criteria) new_spec docs/specs/0005-farewell.md Draft "- none"; sed -i '/^1\. Given/d' docs/specs/0005-farewell.md ;;
  spec-and-code) new_spec docs/specs/0005-farewell.md Draft "- none"; mkdir -p src/main/java/demo; echo "class X {}" > src/main/java/demo/X.java ;;
  spec-edits-another) new_spec docs/specs/0005-farewell.md Draft "- none"; echo "9. Extra." >> docs/specs/0001-greet.md ;;
  spec-two) new_spec docs/specs/0005-farewell.md Draft "- none"; new_spec docs/specs/0006-other.md Draft "- none" ;;
  good) ;;
  crash) exit 7 ;;
  no-commit) commit=0 ;;
  no-report) report=0 ;;
  leftovers) ;;
  architecture-test) echo "// loosened" >> "$ARCH" ;;
  workflow) echo "# changed" >> .github/workflows/ci.yml ;;
  settings) echo "{}" > .claude/settings.json ;;
  spec) echo "2. Extra." >> docs/specs/0001-greet.md ;;
  promotion) echo "# promoted" >> deploy/k8s/overlays/prod/kustomization.yaml ;;
  coverage) sed -i 's|</parent>|</parent><properties><factory.coverage.line.minimum>0.10</factory.coverage.line.minimum></properties>|' pom.xml ;;
  skip-tests) sed -i 's|</parent>|</parent><properties><skipTests>true</skipTests></properties>|' pom.xml ;;
  dependency) sed -i 's|</parent>|</parent><properties><demo.version>1.0.0</demo.version></properties>|' pom.xml ;;
  delete-test) git rm -q "$SOME_TEST" ;;
  # The agent rewrites the runner so its gate would pass anything: the gate job must not run that copy.
  tamper) cat > .github/scripts/factory-run.sh <<'EVIL'
#!/bin/sh
# passes every gate, and hands over its own bundle
[ "$1" = pack ] && git bundle create "$FACTORY_STATE/agent.bundle" "refs/heads/factory/issue-$ISSUE_NUMBER" "^$(cat "$FACTORY_STATE/base")" >/dev/null 2>&1
exit 0
EVIL
          echo "# changed" >> .github/workflows/ci.yml ;;
  # History that doesn't start from the base commit.
  unrelated) git checkout -q --orphan tmp; echo x > x.txt; git add x.txt
             g commit -qm orphan; git branch -M tmp "factory/issue-$ISSUE_NUMBER" ;;
  *) echo "unknown scenario $SCENARIO" >&2; exit 2 ;;
esac
[[ $report -eq 0 ]] || printf '## What was built\nGreeter.\n' > "$FACTORY_REPORT"
[[ $commit -eq 0 ]] || { git add -A && g commit -q -m "change for $SCENARIO"; }
[[ "$SCENARIO" != leftovers ]] || echo "scratch" > notes.txt
echo '{"result":"done"}'
SH
chmod +x "$work/bin/gh" "$work/bin/agent"

export work PATH="$work/bin:$PATH" FAKE_GH="$work/gh" ARCH="$arch" SOME_TEST="$some_test"
export GITHUB_REPOSITORY=acme/demo ISSUE_NUMBER=5 SENDER=owner GH_TOKEN=t
export FACTORY_STATE="$work/state" FACTORY_AGENT_CMD=agent FACTORY_PLUGIN_DIR="$work/p" FACTORY_PUSH_URL="$work/remote.git"
export FACTORY_GIT_NAME=test FACTORY_GIT_EMAIL=test@example.invalid
run=.github/scripts/factory-run.sh
fails=0
TO_GATE="resolve agent pack q:unpack q:gate"
FULL="$TO_GATE r:unpack r:gate r:publish"

fresh() { # back to the untouched project, no state, a collaborator with write access, no existing branch
  git switch -q main 2>/dev/null || true
  git reset -q --hard "$c0"; git clean -qfd
  git branch -q -D factory/issue-5 factory/spec-5 2>/dev/null || true
  rm -rf "$FACTORY_STATE" "$FAKE_GH"/* "$work/q" "$work/r" "$work/state-q" "$work/state-r"
  git --git-dir "$work/remote.git" update-ref -d refs/heads/factory/issue-5
  git --git-dir "$work/remote.git" update-ref -d refs/heads/factory/spec-5
  unset FACTORY_LABEL ISSUE_TITLE GITHUB_EVENT_NAME FACTORY_PAUSED FACTORY_BEFORE GITHUB_SHA
  export SENDER=owner
  echo write > "$FAKE_GH/permission"
  export ISSUE_BODY="Please build docs/specs/0001-greet.md" FACTORY_VERIFY_CMD=true SCENARIO=good
}
runphase() { # <phase>: in the agent job's clone, or q:<phase> (gate job) / r:<phase> (publish job) in a fresh clone of the base
  local ph="$1" job a="$FACTORY_STATE" dir
  case "$ph" in
    q:*|r:*) ;;
    *) "$run" "$ph"; return ;;
  esac
  job="${ph%%:*}"; ph="${ph#*:}"; dir="$work/$job"
  if [[ "$ph" == unpack ]]; then
    rm -rf "$dir" "$work/state-$job"; git clone -q "$work/base.git" "$dir"; git -C "$dir" checkout -q --detach "$c0"
    cp "$dir/$run" "$work/trusted-$job.sh"   # the workflow keeps this copy outside the tree the agent wrote
  fi
  # What the jobs get: the agent job's outputs from before the agent ran, the artifact, and for publish the gated commit.
  ( cd "$dir" && FACTORY_STATE="$work/state-$job" FACTORY_HANDOFF="$a" FACTORY_MODE="$(cat "$a/mode")" \
      FACTORY_BRANCH="$(cat "$a/branch")" FACTORY_BASE="$(cat "$a/base")" FACTORY_BASE_BRANCH="$(cat "$a/base-branch")" \
      FACTORY_SPEC="$(cat "$a/spec" 2>/dev/null || true)" FACTORY_GATE_BUILD="$([[ "$job" == r ]] && echo 0 || echo 1)" \
      FACTORY_GATED_SHA="${GATED:-$(git -C "$work/q" rev-parse HEAD 2>/dev/null || true)}" "$work/trusted-$job.sh" "$ph" )
}
expect() { # expect pass|fail <description> <phase>...
  local want="$1" desc="$2" got=pass out="" phase
  shift 2
  for phase in "$@"; do
    if ! out="$(runphase "$phase" 2>&1)"; then got=fail; break; fi
  done
  if [[ "$got" == "$want" ]]; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc (expected $want, got $got)"
    sed 's/^/    /' <<<"$out"
    fails=1
  fi
}
check() { # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fails=1; fi
}

# resolve: who may start a run, and what it may build
fresh; expect pass "approved spec named in the issue, asked by a collaborator with write access" resolve
check "resolve records the spec, branch, plugin release and base commit" \
  test "$(cat "$FACTORY_STATE/spec") $(cat "$FACTORY_STATE/branch") $(cat "$FACTORY_STATE/plugin-ref") $(cat "$FACTORY_STATE/base")" \
  = "docs/specs/0001-greet.md factory/issue-5 java-pipeline-v9.9.9 $c0"
fresh; echo read > "$FAKE_GH/permission"; expect fail "someone with read access can't start a run" resolve
fresh; : > "$FAKE_GH/permission"; expect fail "someone who isn't a collaborator can't start a run" resolve
fresh; ISSUE_BODY="Add a greeting endpoint please"; expect fail "issue without a spec path is refused" resolve
fresh; ISSUE_BODY="docs/specs/0099-missing.md"; expect fail "spec that isn't on the default branch is refused" resolve
fresh; ISSUE_BODY="docs/specs/0002-draft.md"; expect fail "draft spec is refused" resolve
fresh; ISSUE_BODY="docs/specs/0003-template-status.md"; expect fail "the template's 'Draft | Approved' line doesn't count as approved" resolve
fresh; ISSUE_BODY="docs/specs/0004-no-criteria.md"; expect fail "approved spec without numbered criteria is refused" resolve
fresh; ISSUE_BODY='docs/specs/../../pom.md $(touch pwned) `touch pwned`'; expect fail "path tricks and shell syntax in the issue are not followed" resolve
check "nothing in the issue text was executed" test ! -e pwned
fresh; touch "$FAKE_GH/branch-exists"; expect fail "an existing factory/issue-N branch is refused" resolve
fresh; git rm -q --cached .claude/settings.json; echo '{}' > .claude/settings.json
expect fail "a project that doesn't pin the plugin release is refused" resolve

# agent + gate: the run only counts if the change is clean and the build is green
fresh; expect pass "a committed change with a report and a green build passes the gate" $TO_GATE
check "the agent got the skill, the spec, the plugin directory and a budget" \
  grep -qE '/java-pipeline:new-feature .*docs/specs/0001-greet\.md.* --plugin-dir .* --max-budget-usd 25' "$FAKE_GH/agent-args"
check "the change is on the issue's branch" test "$(git rev-parse --abbrev-ref HEAD)" = factory/issue-5
fresh; FACTORY_VERIFY_CMD=false; expect fail "a red build fails the run" $TO_GATE
fresh; unset FACTORY_AGENT_CMD; PATH="$work/bin:/usr/bin:/bin" expect fail "no Claude credential stops the run before the agent" resolve agent
export FACTORY_AGENT_CMD=agent
for s in crash no-commit no-report leftovers architecture-test workflow settings spec promotion coverage skip-tests delete-test; do
  fresh; SCENARIO="$s"; expect fail "gate refuses: $s" $TO_GATE
done
fresh; SCENARIO=dependency; expect pass "an ordinary pom.xml change is allowed" $TO_GATE
check "(the pom.xml change really was in that commit)" bash -c "git show --stat HEAD | grep -q pom.xml"

# the agent can't make the gate pass by rewriting the runner, and the history must start from the base
fresh; SCENARIO=tamper; expect fail "an agent that rewrites the runner is refused by the base's own copy" $TO_GATE
check "(it was refused for the protected files, not for something else)" \
  grep -q 'changed a protected file: \.github/scripts/factory-run\.sh' "$work/state-q/failure"
fresh; SCENARIO=unrelated; expect fail "history that doesn't start from the base is refused" $TO_GATE
check "(by the unpack phase)" grep -q 'does not start from the base' "$work/state-q/failure"

# publish and failure reports
fresh; GATED=0000000000000000000000000000000000000000 expect fail "publish refuses a commit the gate job did not verify" $FULL
check "(and pushed nothing)" bash -c '! git --git-dir "$0/remote.git" rev-parse --verify -q refs/heads/factory/issue-5' "$work"
fresh; expect pass "the publish job builds nothing (a red build command is not run there)" $TO_GATE
FACTORY_VERIFY_CMD=false expect pass "(publish job)" r:unpack r:gate r:publish
fresh; expect pass "publish pushes the branch and opens the pull request" $FULL
check "the branch is on the remote" git --git-dir "$work/remote.git" rev-parse --verify -q refs/heads/factory/issue-5
check "the pull request targets main from the issue's branch, titled after the spec" \
  grep -qE 'repos/acme/demo/pulls -f title=feat: Greet a customer \(#5\) -f head=factory/issue-5 -f base=main' "$FAKE_GH/calls"
check "the pull request body carries the report and closes the issue" \
  grep -qzE 'What was built.*Closes #5' "$work/state-r/pr-body.md"
check "publish starts CI on the branch (GitHub starts none on a token-opened pull request)" \
  grep -qE '^api --method POST repos/acme/demo/actions/workflows/ci\.yml/dispatches -f ref=factory/issue-5$' "$FAKE_GH/calls"
check "the issue is told that CI was started" \
  grep -qE 'issues/5/comments .*pull/7 is ready for review\. CI was started on the branch' "$FAKE_GH/calls"
fresh; touch "$FAKE_GH/ci-refused"; expect pass "publish still succeeds when CI can't be started" $FULL
check "(and the issue is told to close and reopen the pull request)" \
  grep -qE 'issues/5/comments .*CI could not be started .*close and reopen' "$FAKE_GH/calls"
fresh; FACTORY_PR_TOKEN_SET=true expect pass "publish with FACTORY_PR_TOKEN" $FULL
check "with FACTORY_PR_TOKEN the pull request starts CI itself: no dispatch, no note" \
  bash -c '! grep -qE "ci\.yml/dispatches|CI was started|CI could not" "$FAKE_GH/calls"'
fresh; touch "$FAKE_GH/pr-refused"; expect fail "a pull request GitHub refuses fails publish" $FULL
check "(with GitHub's reason and the setting that fixes it)" \
  grep -q "GitHub refused the pull request: .*not permitted to create or approve pull requests.*Allow GitHub Actions to create" "$work/state-r/failure"
fresh; FACTORY_PUSH_URL="https://x-access-token:SECRET-TOKEN@127.0.0.1:1/x.git" expect fail "a failed push fails publish" $FULL
check "(with the reason, and no credentials in it)" bash -c 'grep -q "could not push factory/issue-5" "$0" && ! grep -q SECRET-TOKEN "$0"' "$work/state-r/failure"
fresh; SCENARIO=workflow; expect fail "a refused run" $TO_GATE
expect pass "failed names the phase and the reason, without calling GitHub" q:failed
check "(failed made no GitHub call)" bash -c '! grep -q "issues/5/comments" "$FAKE_GH/calls"'
FACTORY_WHY="$(cat "$work/state-q/failure")" FACTORY_AT="$(cat "$work/state-q/phase")" expect pass "the report job tells the issue" report
check "the issue comment names the phase and the reason" \
  grep -qE 'issues/5/comments .*stopped in the `gate` phase: gate refused the change: changed a protected file: \.github/workflows/ci\.yml' "$FAKE_GH/calls"
fresh; FACTORY_WHY="" FACTORY_AT="" expect pass "a run that was cancelled or timed out is reported too" report
check "(with that reason)" grep -qE 'issues/5/comments .*cancelled or timed out' "$FAKE_GH/calls"
check "a refused run pushed nothing" bash -c '! git --git-dir "$0/remote.git" rev-parse --verify -q refs/heads/factory/issue-5' "$work"

# factory:spec — an idea becomes a spec pull request (ADR 0019)
idea() { fresh; export FACTORY_LABEL=factory:spec ISSUE_TITLE="Say goodbye" ISSUE_BODY='factory-run-test idea marker $(touch pwned2)' SCENARIO="$1"; }
idea spec-draft; expect pass "an idea becomes a draft spec pull request" $FULL
check "the agent was given the intake skill and the idea as a file, not as text" \
  bash -c 'grep -qE "/java-pipeline:intake .*The idea is in the file " "$FAKE_GH/agent-args" && ! grep -q "idea marker" "$FAKE_GH/agent-args"'
check "nothing in the idea was executed" test ! -e pwned2
check "the spec branch is on the remote" git --git-dir "$work/remote.git" rev-parse --verify -q refs/heads/factory/spec-5
check "the pull request is titled as a spec and doesn't close the issue" \
  bash -c 'grep -qE "pulls -f title=spec: Farewell a customer \(#5\) -f head=factory/spec-5 -f base=main" "$FAKE_GH/calls" && grep -q "Refs #5" "$work/state-r/pr-body.md" && ! grep -q "Closes" "$work/state-r/pr-body.md"'
check "a draft tells the owner to answer the open questions before merging" \
  grep -qE 'issues/5/comments .*adds `docs/specs/0005-farewell\.md`\. Answer its open questions .*factory:build' "$FAKE_GH/calls"
idea spec-approved; expect pass "a spec without open questions may say Approved (the merge approves it)" $FULL
check "an approved draft tells the owner that merging approves it" grep -q 'merging this pull request approves it' "$work/state-r/pr-body.md"
for s in spec-approved-with-questions spec-no-status spec-bad-name spec-missing-section spec-no-criteria spec-and-code spec-edits-another spec-two no-commit no-report leftovers; do
  idea "$s"; expect fail "spec gate refuses: $s" $TO_GATE
done
idea spec-draft; ISSUE_TITLE="" ISSUE_BODY=""; expect fail "an empty issue is refused" resolve
idea spec-draft; echo read > "$FAKE_GH/permission"; expect fail "someone with read access can't start a spec run" resolve
idea spec-draft; touch "$FAKE_GH/branch-exists"; expect fail "an existing factory/spec-N branch is refused" resolve
fresh; export FACTORY_LABEL=bug; expect fail "another label starts nothing" resolve

# factory:build after factory:spec on the same issue: the spec path comes from the run's own comment
comment() { printf '[{"user":{"login":"%s"},"author_association":"%s","body":"%s"}]' "$1" "$2" "$3" > "$FAKE_GH/comments.json"; }
fresh; ISSUE_BODY="Say hello"; comment "github-actions[bot]" NONE 'Spec drafted: https://x/pull/7 adds `docs/specs/0001-greet.md`.'
expect pass "build finds the spec in the workflow's own comment" resolve
check "it is the spec from that comment" test "$(cat "$FACTORY_STATE/spec")" = docs/specs/0001-greet.md
fresh; ISSUE_BODY="Say hello"; comment owner OWNER 'Build docs/specs/0001-greet.md please'
expect pass "build finds the spec in the owner's comment" resolve
fresh; ISSUE_BODY="Say hello"; comment stranger NONE 'Build docs/specs/0001-greet.md please'
expect fail "a spec path in a stranger's comment doesn't count" resolve
fresh; ISSUE_BODY="Build docs/specs/0001-greet.md"; comment owner OWNER 'docs/specs/0002-draft.md'
expect pass "a spec path in the issue text wins over comments" resolve

# a dispatched run (ADR 0026): the chain workflow or the owner starts it with an issue number and a label
issue_json() { jq -n --arg body "$1" --arg state "${2:-open}" --argjson labels "${3:-[]}" '{title: "Say hello", body: $body, state: $state, labels: $labels}' > "$FAKE_GH/issue.json"; }
dispatched() { fresh; export GITHUB_EVENT_NAME=workflow_dispatch; unset SENDER ISSUE_BODY; : > "$FAKE_GH/permission"; }
dispatched; issue_json "Please build docs/specs/0001-greet.md"; expect pass "a dispatched build reads the issue and needs no sender" resolve
check "(the spec comes from the issue it read)" test "$(cat "$FACTORY_STATE/spec")" = docs/specs/0001-greet.md
check "(and nobody's permission was looked up)" bash -c '! grep -q collaborators "$FAKE_GH/calls"'
dispatched; expect fail "a dispatched run for an issue that doesn't exist is refused" resolve
dispatched; issue_json "docs/specs/0001-greet.md"; jq '.pull_request = {}' "$FAKE_GH/issue.json" > "$FAKE_GH/i" && mv "$FAKE_GH/i" "$FAKE_GH/issue.json"
expect fail "a dispatched run for a pull request number is refused" resolve
dispatched; issue_json "docs/specs/0002-draft.md"; expect fail "a dispatched build of a draft spec is refused all the same" resolve
dispatched; export FACTORY_LABEL=factory:spec SCENARIO=spec-draft; issue_json 'factory-run-test idea marker'
expect pass "a dispatched spec run takes the idea from the issue it read" $TO_GATE

# chain (ADR 0026): a merged factory:spec pull request whose spec is approved starts its own build
merged() { # merged <head ref> [<head repo>]: the pull request GitHub reports for the pushed commit
  jq -n --arg ref "$1" --arg repo "${2:-acme/demo}" '[{merged_at: "2026-01-01T00:00:00Z", head: {ref: $ref, repo: {full_name: $repo}}}]' > "$FAKE_GH/pulls.json"
}
push() { # push <spec file> <status>: main gets a commit that writes that spec; the event's before/after
  spec "$1" "$2" "1. Given x, when y, then z."; git add "docs/specs/$1"; g commit -q -m "spec: $1"
  export FACTORY_BEFORE="$c0" GITHUB_SHA; GITHUB_SHA="$(git rev-parse HEAD)"
}
started() { grep -qE '^api --method POST repos/acme/demo/actions/workflows/factory-feature\.yml/dispatches -f ref=main -f inputs\[issue\]=5 -f inputs\[label\]=factory:build$' "$FAKE_GH/calls"; }
nothing() { ! grep -qE 'dispatches|/labels ' "$FAKE_GH/calls"; }
chain() { fresh; export GITHUB_REF_NAME=main; issue_json "Say hello"; merged factory/spec-5; }
chain; push 0007-new.md Approved; expect pass "chain: a merged, approved spec pull request starts the build" chain
check "the issue gets the label factory:build" grep -qE '^api --method POST repos/acme/demo/issues/5/labels -f labels\[\]=factory:build$' "$FAKE_GH/calls"
check "the build is dispatched for that issue" started
check "the issue is told which spec is being built" grep -qE 'issues/5/comments .*Spec approved: `docs/specs/0007-new\.md`' "$FAKE_GH/calls"
chain; push 0002-draft.md Approved; expect pass "chain: a draft the owner set to Approved in the pull request starts the build" chain
check "(dispatched)" started
chain; push 0007-new.md Approved; FACTORY_BEFORE=0000000000000000000000000000000000000000; expect pass "chain: without a usable 'before' it compares with the previous commit" chain
check "(dispatched)" started
chain; push 0007-new.md Draft; expect pass "chain: a merged draft starts nothing" chain
check "(nothing labelled or dispatched)" nothing
chain; push 0001-greet.md Approved; expect pass "chain: a spec that was already approved starts nothing" chain
check "(nothing labelled or dispatched)" nothing
chain; push 0007-new.md Approved; merged feat/my-spec; expect pass "chain: a spec approved outside a factory:spec pull request starts nothing" chain
check "(nothing labelled or dispatched)" nothing
chain; push 0007-new.md Approved; merged factory/spec-5 stranger/demo; expect pass "chain: a fork's branch named factory/spec-N doesn't count" chain
check "(nothing labelled or dispatched)" nothing
chain; push 0007-new.md Approved; export FACTORY_PAUSED=true; expect pass "chain: paused starts nothing" chain
check "(nothing labelled or dispatched)" nothing
chain; push 0007-new.md Approved; issue_json "Say hello" closed; expect pass "chain: a closed issue starts nothing" chain
check "(nothing labelled or dispatched)" nothing
chain; push 0007-new.md Approved; issue_json "Say hello" open '[{"name": "factory:build"}]'; expect pass "chain: an issue that already has factory:build starts nothing more" chain
check "(nothing labelled or dispatched)" nothing
chain; push 0007-new.md Approved; touch "$FAKE_GH/branch-exists"; expect pass "chain: an existing factory/issue-N branch starts nothing" chain
check "(nothing labelled or dispatched)" nothing
chain; push 0007-new.md Approved; touch "$FAKE_GH/dispatch-refused"; expect fail "chain: a build that can't be dispatched fails the run" chain
fresh

[[ "$fails" -eq 0 ]] && echo "factory-run: all cases behave as expected" || { echo "factory-run: test FAILED"; exit 1; }
