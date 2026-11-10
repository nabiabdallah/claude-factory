#!/usr/bin/env bash
# Unattended feature run (claude-factory ADR 0018): an issue labelled `factory:build` that names an approved spec
# is built by the java-pipeline `new-feature` skill and ends in a pull request. The workflow
# .github/workflows/factory-feature.yml calls the phases in order:
#   resolve   who asked, which spec, which branch, which plugin release
#   tools     install the pinned Claude Code CLI and fetch the pinned plugin
#   agent     run the pipeline (the agent has no token that can write to GitHub)
#   gate      the run only counts if the change is committed, stays out of protected files and `./mvnw verify` is green
#   publish   push the branch and open the pull request
#   failed    tell the issue which phase stopped the run
# State is kept between phases in $FACTORY_STATE. Tested with a fake `gh` and a stand-in agent by
# claude-factory's ci/test-factory-run.sh.
set -euo pipefail

# Dependabot can't update this: bump it together with the plugin release the project is pinned to.
claude_code_version=2.1.322

state="${FACTORY_STATE:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/factory-run}"
mkdir -p "$state"

die() { echo "factory-run: $*" >&2; echo "$*" > "$state/failure"; exit 1; }
need() { local v; for v in "$@"; do [[ -n "${!v:-}" ]] || die "$v is not set"; done; }
saved() { [[ -s "$state/$1" ]] || die "no '$1' from an earlier phase (run the phases in order)"; cat "$state/$1"; }

phase="${1:-}"
[[ -n "$phase" ]] || { echo "usage: factory-run.sh resolve|tools|agent|gate|publish|failed" >&2; exit 2; }
[[ "$phase" == failed ]] || echo "$phase" > "$state/phase"

case "$phase" in
  resolve)
    need GITHUB_REPOSITORY ISSUE_NUMBER SENDER
    [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]] || die "issue number is not a number"

    # Only someone who may push to this repository can start a run.
    permission="$(gh api "repos/$GITHUB_REPOSITORY/collaborators/$SENDER/permission" --jq .permission 2>/dev/null || true)"
    case "$permission" in
      admin|maintain|write) ;;
      *) die "$SENDER may not start a factory run (repository permission: ${permission:-none})" ;;
    esac

    # The issue only points at a spec. The spec's text comes from the default branch, where the owner approved it.
    spec="$(grep -oE 'docs/specs/[A-Za-z0-9][A-Za-z0-9._-]*\.md' <<<"${ISSUE_BODY:-}" | head -n 1 || true)"
    [[ -n "$spec" ]] || die "the issue names no spec: put its path (docs/specs/NNNN-name.md) in the issue text"
    [[ -f "$spec" && ! -L "$spec" ]] || die "$spec is not on the default branch: merge the spec first"
    grep -qE '^- Status: *Approved *$' "$spec" || die "$spec is not approved: its header must read '- Status: Approved'"
    sed -n '/^## Acceptance criteria/,/^## /p' "$spec" | grep -qE '^1\. ' \
      || die "$spec has no numbered acceptance criteria"

    # The project is pinned to a plugin release (claude-factory ADR 0015); the run uses exactly that one.
    ref="$(jq -r '.extraKnownMarketplaces["claude-factory"].source.ref // empty' .claude/settings.json 2>/dev/null || true)"
    [[ "$ref" =~ ^java-pipeline-v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || die ".claude/settings.json does not pin the plugin (extraKnownMarketplaces.claude-factory.source.ref = java-pipeline-vX.Y.Z)"

    branch="factory/issue-$ISSUE_NUMBER"
    if gh api "repos/$GITHUB_REPOSITORY/branches/${branch//\//%2F}" --jq .name >/dev/null 2>&1; then
      die "branch $branch already exists: delete it (or close its pull request and delete it) before a new run"
    fi

    echo "$spec" > "$state/spec"
    echo "$branch" > "$state/branch"
    echo "$ref" > "$state/plugin-ref"
    git rev-parse HEAD > "$state/base"
    git rev-parse --abbrev-ref HEAD > "$state/base-branch"
    echo "factory-run: issue #$ISSUE_NUMBER, spec $spec, branch $branch, plugin $ref"
    ;;

  tools)
    ref="$(saved plugin-ref)"
    npm install --global --no-fund --no-audit "@anthropic-ai/claude-code@$claude_code_version"
    rm -rf "$state/claude-factory"
    git clone --quiet --depth 1 --branch "$ref" "${FACTORY_PLUGIN_REPO:-https://github.com/nabiabdallah/claude-factory}" \
      "$state/claude-factory"
    [[ -f "$state/claude-factory/plugins/java-pipeline/.claude-plugin/plugin.json" ]] || die "no java-pipeline plugin at $ref"
    ;;

  agent)
    need ISSUE_NUMBER
    spec="$(saved spec)"; branch="$(saved branch)"
    plugin="${FACTORY_PLUGIN_DIR:-$state/claude-factory/plugins/java-pipeline}"
    [[ -d "$plugin" ]] || die "plugin directory $plugin not found (run the tools phase)"
    [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}${FACTORY_AGENT_CMD:-}" ]] \
      || die "no Claude credential: set the repository secret CLAUDE_CODE_OAUTH_TOKEN (from 'claude setup-token') or ANTHROPIC_API_KEY"

    git config user.name "${FACTORY_GIT_NAME:-github-actions[bot]}"
    git config user.email "${FACTORY_GIT_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
    git switch --quiet --create "$branch"

    export FACTORY_HEADLESS=1
    export FACTORY_REPORT="$state/report.md"
    rm -f "$FACTORY_REPORT"
    prompt="/java-pipeline:new-feature Headless run for issue #$ISSUE_NUMBER. Implement the approved spec $spec. Follow the skill's \"Headless runs\" section. Write the hand-off report to $FACTORY_REPORT."
    # No person can answer a permission prompt, so nothing asks. What limits the agent instead: it holds no
    # token that can write to GitHub, and the gate phase refuses changes to protected files.
    set +e
    "${FACTORY_AGENT_CMD:-claude}" --print "$prompt" \
      --plugin-dir "$plugin" \
      --permission-mode "${FACTORY_PERMISSION_MODE:-bypassPermissions}" \
      --max-budget-usd "${FACTORY_MAX_BUDGET_USD:-25}" \
      --output-format json > "$state/agent.json"
    status=$?
    set -e
    [[ $status -eq 0 ]] || die "the agent stopped with exit code $status (see the agent-run artifact)"
    ;;

  gate)
    spec="$(saved spec)"; base="$(saved base)"
    problems=()

    [[ "$(git rev-list --count "$base..HEAD")" -gt 0 ]] || problems+=("the agent committed nothing")
    leftovers="$(git status --porcelain)"
    [[ -z "$leftovers" ]] || problems+=("uncommitted or untracked files left behind: $(tr '\n' ' ' <<<"$leftovers")")
    [[ -s "$state/report.md" ]] || problems+=("no hand-off report was written")

    # Files only the owner changes: CI and this runner, agent rules and permissions, the architecture rules,
    # the build wrapper, deploy promotions, scan exceptions and specs.
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      case "$f" in
        .github/*|.claude/*|.mvn/*|mvnw|mvnw.cmd|CLAUDE.md|.trivyignore.yaml|.gitignore|deploy/k8s/overlays/*|docs/specs/*|\
        src/test/resources/archunit.properties|src/test/java/*/ArchitectureTest.java)
          problems+=("changed a protected file: $f") ;;
      esac
    done < <(git diff --name-only "$base..HEAD")

    deleted="$(git diff --diff-filter=D --name-only "$base..HEAD" -- src/test)"
    [[ -z "$deleted" ]] || problems+=("deleted tests: $(tr '\n' ' ' <<<"$deleted")")

    # Build rules can't be loosened to get green (claude-factory ADR 0013).
    weakened="$(git diff "$base..HEAD" -- pom.xml | grep -E '^\+[^+]' \
      | grep -E 'factory\.coverage|enforcer\.skip|jacoco\.skip|skipTests|maven\.test\.skip|<excludes?>' || true)"
    [[ -z "$weakened" ]] || problems+=("pom.xml loosens a build rule: $(tr -s ' \n' ' ' <<<"$weakened")")

    if [[ ${#problems[@]} -gt 0 ]]; then
      printf 'factory-run: %s\n' "${problems[@]}" >&2
      die "gate refused the change: ${problems[0]}$([[ ${#problems[@]} -gt 1 ]] && echo " (and $(( ${#problems[@]} - 1 )) more, see the log)")"
    fi

    # The build decides, not the agent's word: the Stop hook gives up after 3 attempts, this doesn't.
    if ! ${FACTORY_VERIFY_CMD:-./mvnw -B -q verify} > "$state/verify.log" 2>&1; then
      tail -n 60 "$state/verify.log" >&2
      die "./mvnw verify is red on the agent's change"
    fi
    [[ -z "$(git status --porcelain)" ]] || die "the build changed tracked files (formatting not applied before commit?)"
    echo "factory-run: gate passed ($(git rev-list --count "$base..HEAD") commits, verify green)"
    ;;

  publish)
    need GITHUB_REPOSITORY ISSUE_NUMBER GH_TOKEN
    spec="$(saved spec)"; branch="$(saved branch)"; base_branch="$(saved base-branch)"
    title="$(sed -n 's/^# Spec: *//p' "$spec" | head -n 1)"
    [[ -n "$title" ]] || title="$(basename "$spec" .md)"

    git push --quiet "${FACTORY_PUSH_URL:-https://x-access-token:$GH_TOKEN@github.com/$GITHUB_REPOSITORY}" \
      "HEAD:refs/heads/$branch"

    {
      cat "$state/report.md"
      printf '\n\n---\nSpec: `%s`. Built unattended by the java-pipeline factory run%s; `./mvnw verify` was green on this commit.\n\nCloses #%s\n' \
        "$spec" "${FACTORY_RUN_URL:+ ($FACTORY_RUN_URL)}" "$ISSUE_NUMBER"
    } > "$state/pr-body.md"
    pr_url="$(gh api "repos/$GITHUB_REPOSITORY/pulls" -f title="feat: $title (#$ISSUE_NUMBER)" -f head="$branch" \
      -f base="$base_branch" -F body=@"$state/pr-body.md" --jq .html_url)"
    [[ -n "$pr_url" ]] || die "the pull request was not created"
    echo "$pr_url" > "$state/pr-url"

    note=""
    [[ "${FACTORY_PR_TOKEN_SET:-false}" == true ]] \
      || note=" CI does not start on a pull request opened with the workflow's own token: close and reopen it, or add the FACTORY_PR_TOKEN secret."
    gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER/comments" \
      -f body="Factory run finished: $pr_url is ready for review.$note" --jq .html_url >/dev/null
    echo "factory-run: opened $pr_url"
    ;;

  failed)
    need GITHUB_REPOSITORY ISSUE_NUMBER
    why="$(cat "$state/failure" 2>/dev/null || echo "the step failed before it could say why")"
    at="$(cat "$state/phase" 2>/dev/null || echo "start")"
    gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER/comments" \
      -f body="Factory run stopped in the \`$at\` phase: $why${FACTORY_RUN_URL:+ ([run]($FACTORY_RUN_URL))}. No pull request was opened. Fix the cause, then remove and re-add the \`factory:build\` label." \
      --jq .html_url >/dev/null || echo "factory-run: could not comment on the issue" >&2
    ;;

  *)
    echo "factory-run: unknown phase '$phase'" >&2; exit 2 ;;
esac
