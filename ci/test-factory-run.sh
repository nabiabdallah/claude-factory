#!/usr/bin/env bash
# Tests a project's .github/scripts/factory-run.sh (factory ADRs 0018 and 0019) on a throwaway copy, without GitHub, Maven
# or a Claude credential: `gh` is a fake that records its calls, the agent is a stand-in that makes the commits a
# scenario asks for, and `./mvnw verify` is replaced by a command that passes or fails.
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

# Fake gh: answers from files in $FAKE_GH, appends every call to $FAKE_GH/calls.
mkdir -p "$work/bin" "$work/gh"
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH/calls"
case "$2" in
  */collaborators/*/permission) cat "$FAKE_GH/permission" ;;
  */branches/*) [[ -f "$FAKE_GH/branch-exists" ]] && echo branch || exit 1 ;;
  */pulls) echo "https://github.com/acme/demo/pull/7" ;;
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
  *) echo "unknown scenario $SCENARIO" >&2; exit 2 ;;
esac
[[ $report -eq 0 ]] || printf '## What was built\nGreeter.\n' > "$FACTORY_REPORT"
[[ $commit -eq 0 ]] || { git add -A && g commit -q -m "change for $SCENARIO"; }
[[ "$SCENARIO" != leftovers ]] || echo "scratch" > notes.txt
echo '{"result":"done"}'
SH
chmod +x "$work/bin/gh" "$work/bin/agent"

export PATH="$work/bin:$PATH" FAKE_GH="$work/gh" ARCH="$arch" SOME_TEST="$some_test"
export GITHUB_REPOSITORY=acme/demo ISSUE_NUMBER=5 SENDER=owner GH_TOKEN=t
export FACTORY_STATE="$work/state" FACTORY_AGENT_CMD=agent FACTORY_PLUGIN_DIR="$work/p" FACTORY_PUSH_URL="$work/remote.git"
export FACTORY_GIT_NAME=test FACTORY_GIT_EMAIL=test@example.invalid
run=.github/scripts/factory-run.sh
fails=0

fresh() { # back to the untouched project, no state, a collaborator with write access, no existing branch
  git switch -q main 2>/dev/null || true
  git reset -q --hard "$c0"; git clean -qfd
  git branch -q -D factory/issue-5 factory/spec-5 2>/dev/null || true
  rm -rf "$FACTORY_STATE" "$FAKE_GH"/*
  git --git-dir "$work/remote.git" update-ref -d refs/heads/factory/issue-5
  git --git-dir "$work/remote.git" update-ref -d refs/heads/factory/spec-5
  unset FACTORY_LABEL ISSUE_TITLE
  echo write > "$FAKE_GH/permission"
  export ISSUE_BODY="Please build docs/specs/0001-greet.md" FACTORY_VERIFY_CMD=true SCENARIO=good
}
expect() { # expect pass|fail <description> <phase>...
  local want="$1" desc="$2" got=pass out="" phase
  shift 2
  for phase in "$@"; do
    if ! out="$("$run" "$phase" 2>&1)"; then got=fail; break; fi
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
fresh; expect pass "a committed change with a report and a green build passes the gate" resolve agent gate
check "the agent got the skill, the spec, the plugin directory and a budget" \
  grep -qE '/java-pipeline:new-feature .*docs/specs/0001-greet\.md.* --plugin-dir .* --max-budget-usd 25' "$FAKE_GH/agent-args"
check "the change is on the issue's branch" test "$(git rev-parse --abbrev-ref HEAD)" = factory/issue-5
fresh; FACTORY_VERIFY_CMD=false; expect fail "a red build fails the run" resolve agent gate
fresh; unset FACTORY_AGENT_CMD; PATH="$work/bin:/usr/bin:/bin" expect fail "no Claude credential stops the run before the agent" resolve agent
export FACTORY_AGENT_CMD=agent
for s in crash no-commit no-report leftovers architecture-test workflow settings spec promotion coverage skip-tests delete-test; do
  fresh; SCENARIO="$s"; expect fail "gate refuses: $s" resolve agent gate
done
fresh; SCENARIO=dependency; expect pass "an ordinary pom.xml change is allowed" resolve agent gate
check "(the pom.xml change really was in that commit)" bash -c "git show --stat HEAD | grep -q pom.xml"

# publish and failure reports
fresh; expect pass "publish pushes the branch and opens the pull request" resolve agent gate publish
check "the branch is on the remote" git --git-dir "$work/remote.git" rev-parse --verify -q refs/heads/factory/issue-5
check "the pull request targets main from the issue's branch, titled after the spec" \
  grep -qE 'repos/acme/demo/pulls -f title=feat: Greet a customer \(#5\) -f head=factory/issue-5 -f base=main' "$FAKE_GH/calls"
check "the pull request body carries the report and closes the issue" \
  grep -qzE 'What was built.*Closes #5' "$FACTORY_STATE/pr-body.md"
check "the issue is told, with the note about CI on token-opened pull requests" \
  grep -qE 'issues/5/comments .*pull/7 is ready for review\. CI does not start' "$FAKE_GH/calls"
fresh; FACTORY_PR_TOKEN_SET=true expect pass "publish with FACTORY_PR_TOKEN" resolve agent gate publish
check "no CI note when FACTORY_PR_TOKEN is set" bash -c '! grep -q "CI does not start" "$FAKE_GH/calls"'
fresh; SCENARIO=workflow; expect fail "a refused run" resolve agent gate
expect pass "failed reports to the issue" failed
check "the issue comment names the phase and the reason" \
  grep -qE 'issues/5/comments .*stopped in the `gate` phase: gate refused the change: changed a protected file: \.github/workflows/ci\.yml' "$FAKE_GH/calls"
check "a refused run pushed nothing" bash -c '! git --git-dir "$0/remote.git" rev-parse --verify -q refs/heads/factory/issue-5' "$work"

# factory:spec — an idea becomes a spec pull request (ADR 0019)
idea() { fresh; export FACTORY_LABEL=factory:spec ISSUE_TITLE="Say goodbye" ISSUE_BODY='factory-run-test idea marker $(touch pwned2)' SCENARIO="$1"; }
idea spec-draft; expect pass "an idea becomes a draft spec pull request" resolve agent gate publish
check "the agent was given the intake skill and the idea as a file, not as text" \
  bash -c 'grep -qE "/java-pipeline:intake .*The idea is in the file " "$FAKE_GH/agent-args" && ! grep -q "idea marker" "$FAKE_GH/agent-args"'
check "nothing in the idea was executed" test ! -e pwned2
check "the spec branch is on the remote" git --git-dir "$work/remote.git" rev-parse --verify -q refs/heads/factory/spec-5
check "the pull request is titled as a spec and doesn't close the issue" \
  bash -c 'grep -qE "pulls -f title=spec: Farewell a customer \(#5\) -f head=factory/spec-5 -f base=main" "$FAKE_GH/calls" && grep -q "Refs #5" "$FACTORY_STATE/pr-body.md" && ! grep -q "Closes" "$FACTORY_STATE/pr-body.md"'
check "a draft tells the owner to answer the open questions before merging" \
  grep -qE 'issues/5/comments .*adds `docs/specs/0005-farewell\.md`\. Answer its open questions .*factory:build' "$FAKE_GH/calls"
idea spec-approved; expect pass "a spec without open questions may say Approved (the merge approves it)" resolve agent gate publish
check "an approved draft tells the owner that merging approves it" grep -q 'merging this pull request approves it' "$FACTORY_STATE/pr-body.md"
for s in spec-approved-with-questions spec-no-status spec-bad-name spec-missing-section spec-no-criteria spec-and-code spec-edits-another spec-two no-commit no-report leftovers; do
  idea "$s"; expect fail "spec gate refuses: $s" resolve agent gate
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

[[ "$fails" -eq 0 ]] && echo "factory-run: all cases behave as expected" || { echo "factory-run: test FAILED"; exit 1; }
