#!/usr/bin/env bash
# Unattended factory runs (claude-factory ADRs 0018 and 0019), started by a label on an issue:
#   factory:spec    the issue is an idea; the java-pipeline `intake` skill drafts a spec and the run ends in a
#                   pull request that adds it. Merging that pull request is how the owner approves the spec.
#   factory:build   the issue names an approved spec (in its text, or in the run's own "spec drafted" comment);
#                   the `new-feature` skill builds it and the run ends in a pull request with the code.
# The workflow .github/workflows/factory-feature.yml calls the phases in order:
#   resolve   who asked, what to do, which branch, which plugin release
#   tools     install the pinned Claude Code CLI and fetch the pinned plugin
#   agent     run the skill (the agent has no token that can write to GitHub)
#   gate      spec: exactly one new, complete spec file. build: committed, protected files untouched, `./mvnw verify` green
#   publish   push the branch and open the pull request
#   failed    tell the issue which phase stopped the run
# State is kept between phases in $FACTORY_STATE. Tested with a fake `gh` and a stand-in agent by
# claude-factory's ci/test-factory-run.sh.
set -euo pipefail

# Dependabot can't update this: bump it together with the plugin release the project is pinned to.
claude_code_version=2.1.322

spec_path='docs/specs/[A-Za-z0-9][A-Za-z0-9._-]*\.md'
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

    # The project is pinned to a plugin release (claude-factory ADR 0015); the run uses exactly that one.
    ref="$(jq -r '.extraKnownMarketplaces["claude-factory"].source.ref // empty' .claude/settings.json 2>/dev/null || true)"
    [[ "$ref" =~ ^java-pipeline-v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || die ".claude/settings.json does not pin the plugin (extraKnownMarketplaces.claude-factory.source.ref = java-pipeline-vX.Y.Z)"

    case "${FACTORY_LABEL:-factory:build}" in
      factory:build)
        mode=build; branch="factory/issue-$ISSUE_NUMBER"
        # The issue only points at a spec. The spec's text comes from the default branch, where the owner approved it.
        spec="$(grep -oE "$spec_path" <<<"${ISSUE_BODY:-}" | head -n 1 || true)"
        if [[ -z "$spec" ]]; then
          # Or an earlier factory:spec run on this issue named it. Only comments by this workflow or by people
          # who can push count: anyone can comment on a public repository.
          trusted="$(gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER/comments?per_page=100" 2>/dev/null \
            | jq -r '[.[] | select(.user.login == "github-actions[bot]" or (.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))) | .body] | join("\n")' 2>/dev/null || true)"
          spec="$(grep -oE "$spec_path" <<<"$trusted" | tail -n 1 || true)"
        fi
        [[ -n "$spec" ]] || die "the issue names no spec: put its path (docs/specs/NNNN-name.md) in the issue text, or draft one with the factory:spec label"
        [[ -f "$spec" && ! -L "$spec" ]] || die "$spec is not on the default branch: merge the spec first"
        grep -qE '^- Status: *Approved *$' "$spec" || die "$spec is not approved: its header must read '- Status: Approved'"
        sed -n '/^## Acceptance criteria/,/^## /p' "$spec" | grep -qE '^1\. ' \
          || die "$spec has no numbered acceptance criteria"
        echo "$spec" > "$state/spec"
        ;;
      factory:spec)
        mode=spec; branch="factory/spec-$ISSUE_NUMBER"
        [[ -n "${ISSUE_TITLE:-}${ISSUE_BODY:-}" ]] || die "the issue is empty: describe the idea in its title and text"
        # The idea reaches the agent as a file to read, never as part of a command or of the prompt.
        printf '# %s\n\n%s\n' "${ISSUE_TITLE:-}" "${ISSUE_BODY:-}" > "$state/idea.md"
        ;;
      *) die "label '${FACTORY_LABEL}' does not start a factory run" ;;
    esac

    if gh api "repos/$GITHUB_REPOSITORY/branches/${branch//\//%2F}" --jq .name >/dev/null 2>&1; then
      die "branch $branch already exists: delete it (or close its pull request and delete it) before a new run"
    fi

    echo "$mode" > "$state/mode"
    echo "$branch" > "$state/branch"
    echo "$ref" > "$state/plugin-ref"
    git rev-parse HEAD > "$state/base"
    git rev-parse --abbrev-ref HEAD > "$state/base-branch"
    echo "factory-run: issue #$ISSUE_NUMBER, $mode run, branch $branch, plugin $ref"
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
    mode="$(saved mode)"; branch="$(saved branch)"
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
    if [[ "$mode" == spec ]]; then
      export FACTORY_IDEA="$state/idea.md"
      prompt="/java-pipeline:intake Headless run for issue #$ISSUE_NUMBER. The idea is in the file $FACTORY_IDEA. Follow the skill's \"Headless runs\" section. Write the report to $FACTORY_REPORT."
    else
      prompt="/java-pipeline:new-feature Headless run for issue #$ISSUE_NUMBER. Implement the approved spec $(saved spec). Follow the skill's \"Headless runs\" section. Write the hand-off report to $FACTORY_REPORT."
    fi
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
    mode="$(saved mode)"; base="$(saved base)"
    problems=()

    [[ "$(git rev-list --count "$base..HEAD")" -gt 0 ]] || problems+=("the agent committed nothing")
    leftovers="$(git status --porcelain)"
    [[ -z "$leftovers" ]] || problems+=("uncommitted or untracked files left behind: $(tr '\n' ' ' <<<"$leftovers")")
    [[ -s "$state/report.md" ]] || problems+=("no hand-off report was written")

    if [[ "$mode" == spec ]]; then
      # A spec run adds one spec file and nothing else. It is complete, and "Approved" only with no open question.
      changes="$(git diff --name-status "$base..HEAD")"
      if [[ "$changes" =~ ^A[[:space:]]+(docs/specs/[0-9]{4}-[a-z0-9]+(-[a-z0-9]+)*\.md)$ ]]; then
        spec="${BASH_REMATCH[1]}"
        for heading in Problem Scope Contract Authorization "Acceptance criteria" "Failure modes" Rollout Non-functional "Open questions"; do
          grep -qxF "## $heading" "$spec" || problems+=("$spec has no '## $heading' section")
        done
        grep -qE '^# Spec: .*[^ >]$' "$spec" || problems+=("$spec has no '# Spec: <name>' title")
        sed -n '/^## Acceptance criteria/,/^## /p' "$spec" | grep -qE '^1\. ' || problems+=("$spec has no numbered acceptance criteria")
        status="$(sed -n 's/^- Status: *//p' "$spec" | head -n 1)"
        open="$(sed -n '/^## Open questions/,$p' "$spec" | tail -n +2 | grep -vE '^\s*$' | grep -viE '^-? *\(?none\.?\)?$' || true)"
        case "$status" in
          Draft) ;;
          Approved) [[ -z "$open" ]] || problems+=("$spec says Approved but still has open questions") ;;
          *) problems+=("$spec must say '- Status: Draft' or '- Status: Approved' (found '${status:-nothing}')") ;;
        esac
        echo "$spec" > "$state/spec"; echo "$status" > "$state/spec-status"
      else
        problems+=("a spec run must add exactly one file docs/specs/NNNN-name.md and change nothing else; found: $(tr -s '\t\n' ' ' <<<"$changes")")
      fi
      if [[ ${#problems[@]} -gt 0 ]]; then
        printf 'factory-run: %s\n' "${problems[@]}" >&2
        die "gate refused the spec: ${problems[0]}$([[ ${#problems[@]} -gt 1 ]] && echo " (and $(( ${#problems[@]} - 1 )) more, see the log)")"
      fi
      echo "factory-run: gate passed (spec $spec, status $status)"
      exit 0
    fi

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
    mode="$(saved mode)"
    title="$(sed -n 's/^# Spec: *//p' "$spec" | head -n 1)"
    [[ -n "$title" ]] || title="$(basename "$spec" .md)"

    git push --quiet "${FACTORY_PUSH_URL:-https://x-access-token:$GH_TOKEN@github.com/$GITHUB_REPOSITORY}" \
      "HEAD:refs/heads/$branch"

    run="${FACTORY_RUN_URL:+ ($FACTORY_RUN_URL)}"
    if [[ "$mode" == spec ]]; then
      status="$(saved spec-status)"
      pr_title="spec: $title (#$ISSUE_NUMBER)"
      if [[ "$status" == Approved ]]; then
        next="It has no open questions and says \`- Status: Approved\`: merging this pull request approves it."
        todo="Review it and merge to approve it"
      else
        next="It has open questions, so it says \`- Status: Draft\`. Answer them in the file, set \`- Status: Approved\`, then merge: that approves it."
        todo="Answer its open questions in the file, set \`- Status: Approved\` and merge"
      fi
      footer="$(printf 'Adds `%s`, drafted unattended from issue #%s by the java-pipeline factory run%s. %s\n\nRefs #%s' "$spec" "$ISSUE_NUMBER" "$run" "$next" "$ISSUE_NUMBER")"
      done_note="Spec drafted: PR_URL adds \`$spec\`. $todo, then put the label \`factory:build\` on this issue to build it."
    else
      pr_title="feat: $title (#$ISSUE_NUMBER)"
      footer="$(printf 'Spec: `%s`. Built unattended by the java-pipeline factory run%s; `./mvnw verify` was green on this commit.\n\nCloses #%s' "$spec" "$run" "$ISSUE_NUMBER")"
      done_note="Factory run finished: PR_URL is ready for review."
    fi
    { cat "$state/report.md"; printf '\n\n---\n%s\n' "$footer"; } > "$state/pr-body.md"
    pr_url="$(gh api "repos/$GITHUB_REPOSITORY/pulls" -f title="$pr_title" -f head="$branch" \
      -f base="$base_branch" -F body=@"$state/pr-body.md" --jq .html_url)"
    [[ -n "$pr_url" ]] || die "the pull request was not created"
    echo "$pr_url" > "$state/pr-url"

    note=""
    [[ "${FACTORY_PR_TOKEN_SET:-false}" == true ]] \
      || note=" CI does not start on a pull request opened with the workflow's own token: close and reopen it, or add the FACTORY_PR_TOKEN secret."
    gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER/comments" \
      -f body="${done_note//PR_URL/$pr_url}$note" --jq .html_url >/dev/null
    echo "factory-run: opened $pr_url"
    ;;

  failed)
    need GITHUB_REPOSITORY ISSUE_NUMBER
    why="$(cat "$state/failure" 2>/dev/null || echo "the step failed before it could say why")"
    at="$(cat "$state/phase" 2>/dev/null || echo "start")"
    gh api "repos/$GITHUB_REPOSITORY/issues/$ISSUE_NUMBER/comments" \
      -f body="Factory run stopped in the \`$at\` phase: $why${FACTORY_RUN_URL:+ ([run]($FACTORY_RUN_URL))}. No pull request was opened. Fix the cause, then remove and re-add the label." \
      --jq .html_url >/dev/null || echo "factory-run: could not comment on the issue" >&2
    ;;

  *)
    echo "factory-run: unknown phase '$phase'" >&2; exit 2 ;;
esac
