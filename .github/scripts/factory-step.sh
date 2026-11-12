#!/usr/bin/env bash
# Headless factory steps (factory ADR 0022): the next queued step of docs/ROADMAP.md, run in GitHub Actions and
# ended in a pull request opened by the factory's App. .github/workflows/factory-step.yml calls the phases:
#   agent job  (no GitHub token; the Claude credential only)
#     resolve   which step (the input, or the first unfinished one), refuse while paused or while a step PR is open
#     tools     install the pinned Claude Code CLI
#     agent     run the step: "Read docs/ROADMAP.md and continue with <step>", headless
#     pack      everything committed, a report written; hand over a git bundle of the commits and the report
#   publish job  (a fresh checkout of the base commit: nothing the agent touched runs here)
#     gate      the bundle holds commits on top of the base; flags protected files (risk:high); refuses deleted tests
#     publish   push the branch and open the pull request with the App's token
#   either job
#     failed    say in the job summary which phase stopped the run and why
# State lives in $FACTORY_STATE. Tested with a fake `gh` and a stand-in agent by ci/test-factory-step.sh.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# One CLI pin for the factory: the one the service runner uses (bumped together, ADR 0018).
claude_code_version="$(sed -n 's/^claude_code_version=//p' "$here/../../plugins/java-pipeline/templates/skeleton/.github/scripts/factory-run.sh" 2>/dev/null || true)"
state="${FACTORY_STATE:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/factory-step}"
mkdir -p "$state"

die() { echo "factory-step: $*" >&2; echo "$*" > "$state/failure"; exit 1; }
need() { local v; for v in "$@"; do [[ -n "${!v:-}" ]] || die "$v is not set"; done; }
saved() { [[ -s "$state/$1" ]] || die "no '$1' from an earlier phase (run the phases in order)"; cat "$state/$1"; }
output() { [[ -z "${GITHUB_OUTPUT:-}" ]] || echo "$1=$2" >> "$GITHUB_OUTPUT"; }

# Files whose change makes the PR risk:high (ADR 0020): CI and workflows, the guardrails and the App, the rules
# agents follow, and the ADRs that set those rules.
protected_re='^(\.github/|\.claude/|CLAUDE\.md$|ci/protect-repo\.sh$|ci/factory-app/|ci/create-factory-app\.sh$|docs/factory-adr/00(17|20|21|22)-)'

phase="${1:-}"
[[ -n "$phase" ]] || { echo "usage: factory-step.sh resolve|tools|agent|pack|gate|publish|failed" >&2; exit 2; }
[[ "$phase" == failed ]] || echo "$phase" > "$state/phase"

case "$phase" in
  resolve)
    need GITHUB_REPOSITORY
    [[ "${FACTORY_PAUSED:-}" != true ]] || die "the factory is paused (repository variable FACTORY_PAUSED=true)"
    # Queue rows look like "| B2 | ..." (to do), "| B1 ✅ | ..." (done) or "| A2 (built, …) | ..." (waiting on the
    # owner). Only a bare id is runnable.
    runnable="$(sed -n 's/^| \([AB][0-9][0-9]*[a-z]\{0,1\}\) |.*/\1/p' docs/ROADMAP.md)"
    [[ -n "$runnable" ]] || die "no unfinished step in the roadmap's queue"
    if [[ -n "${STEP:-}" ]]; then
      [[ "$STEP" =~ ^[AB][0-9]{1,2}[a-z]?$ ]] || die "step must look like B2 or B2a"
      grep -qx "$STEP" <<<"$runnable" || die "$STEP is not an unfinished step in the roadmap's queue"
      step="$STEP"
    else
      step="$(head -n 1 <<<"$runnable")"
    fi
    branch="factory/step-${step,,}"
    open="$(gh pr list --repo "$GITHUB_REPOSITORY" --state open --json headRefName --jq '.[].headRefName' | grep '^factory/step-' || true)"
    [[ -z "$open" ]] || die "a step PR is still open ($(tr '\n' ' ' <<<"$open")): one step at a time"
    if gh api "repos/$GITHUB_REPOSITORY/branches/${branch//\//%2F}" --jq .name >/dev/null 2>&1; then
      die "branch $branch already exists: delete it before a new run"
    fi
    echo "$step" > "$state/step"; echo "$branch" > "$state/branch"; git rev-parse HEAD > "$state/base"
    output step "$step"; output branch "$branch"; output base "$(cat "$state/base")"
    echo "factory-step: step $step, branch $branch, base $(cat "$state/base")"
    ;;

  tools)
    [[ "$claude_code_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "no pinned Claude Code version found"
    npm install --global --no-fund --no-audit "@anthropic-ai/claude-code@$claude_code_version"
    ;;

  agent)
    step="$(saved step)"; branch="$(saved branch)"
    [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}${FACTORY_AGENT_CMD:-}" ]] \
      || die "no Claude credential: set the repository secret CLAUDE_CODE_OAUTH_TOKEN (from 'claude setup-token')"
    git switch --quiet --create "$branch"
    export FACTORY_HEADLESS=1 FACTORY_STEP="$step" FACTORY_REPORT="$state/report.md"
    rm -f "$FACTORY_REPORT"
    prompt="Headless factory step run. Read docs/ROADMAP.md and continue with step $step. Follow the \"Headless step runs\" rules in CLAUDE.md. Write the pull request description to $FACTORY_REPORT."
    # Nobody can answer a permission prompt. The limits are elsewhere: this job holds no GitHub token, the
    # publish job runs only trusted code on the agent's commits, and a PR merges only on green checks.
    set +e
    "${FACTORY_AGENT_CMD:-claude}" --print "$prompt" \
      --permission-mode "${FACTORY_PERMISSION_MODE:-bypassPermissions}" \
      --max-budget-usd "${FACTORY_MAX_BUDGET_USD:-25}" \
      --output-format json > "$state/agent.json"
    status=$?
    set -e
    [[ $status -eq 0 ]] || die "the agent stopped with exit code $status (see the agent-step artifact)"
    ;;

  pack)
    branch="$(saved branch)"; base="$(saved base)"
    [[ -s "$state/report.md" ]] || die "no report was written (the agent's stop reason is in agent.json)"
    leftovers="$(git status --porcelain)"
    [[ -z "$leftovers" ]] || die "uncommitted or untracked files left behind: $(tr '\n' ' ' <<<"$leftovers")"
    [[ "$(git rev-list --count "$base..HEAD")" -gt 0 ]] || die "the agent committed nothing"
    git bundle create "$state/agent.bundle" "refs/heads/$branch" "^$base" >/dev/null 2>&1 || die "could not bundle the commits"
    echo "factory-step: packed $(git rev-list --count "$base..HEAD") commits"
    ;;

  gate)
    # Runs in the publish job from a checkout of the base: STEP, BRANCH and BASE come from the agent job's resolve
    # phase (before the agent ran); the bundle and the report come from the agent and are checked, not trusted.
    need STEP BRANCH BASE FACTORY_HANDOFF
    [[ "$STEP" =~ ^[AB][0-9]{1,2}[a-z]?$ && "$BRANCH" == "factory/step-${STEP,,}" && "$BASE" =~ ^[0-9a-f]{40}$ ]] \
      || die "unexpected step, branch or base from the agent job"
    [[ "$(git rev-parse HEAD)" == "$BASE" ]] || die "this checkout is not the base commit $BASE"
    bundle="$FACTORY_HANDOFF/agent.bundle"; report="$FACTORY_HANDOFF/report.md"
    [[ -f "$bundle" && -s "$report" ]] || die "the agent job handed over no bundle or no report"
    git bundle verify -q "$bundle" >/dev/null 2>&1 || die "the bundle is not valid on top of the base"
    git fetch -q "$bundle" "refs/heads/$BRANCH:refs/heads/$BRANCH" 2>/dev/null || die "the bundle has no $BRANCH"
    git merge-base --is-ancestor "$BASE" "$BRANCH" || die "$BRANCH does not start from the base"
    commits="$(git rev-list --count "$BASE..$BRANCH")"
    [[ "$commits" -gt 0 ]] || die "no commits on $BRANCH"
    (( $(wc -c < "$report") <= 60000 )) || die "the report is over 60000 bytes"

    deleted="$(git diff --diff-filter=D --name-only "$BASE..$BRANCH" -- 'ci/test-*' || true)"
    [[ -z "$deleted" ]] || die "deleted tests: $(tr '\n' ' ' <<<"$deleted")"
    git diff --name-only "$BASE..$BRANCH" | grep -E "$protected_re" > "$state/protected" || true
    cp "$report" "$state/report.md"
    echo "$STEP" > "$state/step"; echo "$BRANCH" > "$state/branch"
    if [[ -s "$state/protected" ]]; then
      echo "factory-step: gate passed, risk:high (protected files: $(tr '\n' ' ' < "$state/protected"))"
    else
      echo "factory-step: gate passed ($commits commits)"
    fi
    ;;

  publish)
    need GITHUB_REPOSITORY GH_TOKEN
    step="$(saved step)"; branch="$(saved branch)"
    git push --quiet "${FACTORY_PUSH_URL:-https://x-access-token:$GH_TOKEN@github.com/$GITHUB_REPOSITORY}" \
      "refs/heads/$branch:refs/heads/$branch"
    title="$(sed -n 's/^# *//p' "$state/report.md" | head -n 1 | cut -c1-120)"
    [[ -n "$title" ]] || title="factory step $step"
    {
      cat "$state/report.md"
      printf '\n\n---\nQueue step %s, run unattended by the factory%s. The plan is this description; merging approves it (ADR 0017).\n' \
        "$step" "${FACTORY_RUN_URL:+ ([run]($FACTORY_RUN_URL))}"
      if [[ -s "$state/protected" ]]; then
        printf '\n**risk:high**: changes protected files, so only the owner merges it:\n'
        sed 's/^/- `/; s/$/`/' "$state/protected"
      fi
    } > "$state/pr-body.md"
    pr_url="$(gh api "repos/$GITHUB_REPOSITORY/pulls" -f title="$title" -f head="$branch" -f base=main \
      -F body=@"$state/pr-body.md" --jq .html_url)"
    [[ -n "$pr_url" ]] || die "the pull request was not created"
    if [[ -s "$state/protected" ]]; then
      gh api "repos/$GITHUB_REPOSITORY/labels" -f name=risk:high -f color=B60205 \
        -f description="Only the owner merges (ADR 0020)" >/dev/null 2>&1 || true
      gh api "repos/$GITHUB_REPOSITORY/issues/${pr_url##*/}/labels" -f 'labels[]=risk:high' >/dev/null
    fi
    echo "$pr_url" > "$state/pr-url"
    [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "Step $step: $pr_url" >> "$GITHUB_STEP_SUMMARY"
    echo "factory-step: opened $pr_url"
    ;;

  failed)
    why="$(cat "$state/failure" 2>/dev/null || echo "the step failed before it could say why")"
    at="$(cat "$state/phase" 2>/dev/null || echo "start")"
    msg="Factory step stopped in the \`$at\` phase: $why. No pull request was opened."
    echo "$msg" >&2
    [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "$msg" >> "$GITHUB_STEP_SUMMARY"
    ;;

  *)
    echo "factory-step: unknown phase '$phase'" >&2; exit 2 ;;
esac
