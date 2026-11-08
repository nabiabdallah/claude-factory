#!/usr/bin/env bash
# Repo guardrails (factory ADR 0016): applies the owner-approved rulesets and security settings to a public repo,
# idempotently. Run once per repo with an admin `gh` login; re-run any time to restore the settings.
#   ci/protect-repo.sh [--dry-run] <owner/repo> <factory|service>
# --dry-run prints the requests as JSON lines and calls nothing. Rulesets are matched by name ("main",
# "release tags"): created if missing, replaced if present; other rulesets are left alone.
set -euo pipefail

usage() { echo "usage: $0 [--dry-run] <owner/repo> <factory|service>" >&2; exit 2; }
dry=0
[[ "${1:-}" == "--dry-run" ]] && { dry=1; shift; }
[[ $# -eq 2 ]] || usage
repo="$1" kind="$2"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
case "$kind" in
  # Required checks are the status contexts the repo's CI reports: a job's `name:`, or its id if it has none.
  factory) checks='["Template builds and new-project works", "Kubernetes manifests render and match the schemas"]' ;;
  service) checks='["verify", "manifests"]' ;;
  *) usage ;;
esac
command -v jq >/dev/null || { echo "needs jq" >&2; exit 2; }

github_actions=15368 # the GitHub Actions app: only its runs may satisfy a required check
admin_role=5         # the built-in "Repository admin" role

main_ruleset="$(jq -n --argjson checks "$checks" --argjson app "$github_actions" --argjson admin "$admin_role" '{
  name: "main", target: "branch", enforcement: "active",
  conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
  # Admins may merge a PR whose check is broken (to fix the check); nobody pushes to main directly.
  bypass_actors: [{actor_id: $admin, actor_type: "RepositoryRole", bypass_mode: "pull_request"}],
  rules: [
    {type: "deletion"},
    {type: "non_fast_forward"},
    # 0 approvals: the owner authors every PR and GitHub never lets an author approve their own (ADR 0016).
    {type: "pull_request", parameters: {required_approving_review_count: 0, dismiss_stale_reviews_on_push: false,
      require_code_owner_review: false, require_last_push_approval: false, required_review_thread_resolution: false}},
    {type: "required_status_checks", parameters: {strict_required_status_checks_policy: true,
      required_status_checks: [$checks[] | {context: ., integration_id: $app}]}}
  ]}')"

# Projects pin these tags (ADR 0015): they may be created, never moved or deleted, and nobody bypasses that.
tag_ruleset='{
  "name": "release tags", "target": "tag", "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/tags/java-pipeline-v*", "refs/tags/factory-parent-v*"], "exclude": []}},
  "bypass_actors": [],
  "rules": [{"type": "update"}, {"type": "deletion"}, {"type": "non_fast_forward"}]
}'

security='{"security_and_analysis": {"secret_scanning": {"status": "enabled"},
  "secret_scanning_push_protection": {"status": "enabled"}}}'
if [[ "$kind" == factory ]]; then
  # base-image.yml opens PRs with GITHUB_TOKEN, which needs this switch (ADR 0009).
  workflow='{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": true}'
else
  workflow='{"default_workflow_permissions": "read"}'
fi
codeql='{"state": "configured", "languages": ["java-kotlin", "actions"], "query_suite": "default"}'

# --- requests
existing='[]'
send() { # send <METHOD> <path> [json body]
  local method="$1" path="$2" body="${3:-}"
  if (( dry )); then
    jq -c -n --arg m "$method" --arg p "$path" --argjson b "${body:-null}" '{method: $m, path: $p, body: $b}'
  elif [[ -n "$body" ]]; then
    gh api --method "$method" "$path" --input - <<<"$body" >/dev/null
  else
    gh api --method "$method" "$path" >/dev/null
  fi
}
upsert_ruleset() { # upsert_ruleset <json body>
  local body="$1" name id
  name="$(jq -r .name <<<"$body")"
  if (( dry )); then
    jq -c -n --arg p "repos/$repo/rulesets" --arg n "$name" --argjson b "$body" \
      '{method: "UPSERT-RULESET", path: $p, name: $n, body: $b}'
    return
  fi
  id="$(jq -r --arg n "$name" 'first(.[] | select(.name == $n) | .id) // empty' <<<"$existing")"
  if [[ -n "$id" ]]; then
    send PUT "repos/$repo/rulesets/$id" "$body"; echo "updated ruleset '$name' ($id)"
  else
    send POST "repos/$repo/rulesets" "$body"; echo "created ruleset '$name'"
  fi
}

if (( ! dry )); then
  command -v gh >/dev/null || { echo "needs gh (logged in as a repo admin)" >&2; exit 2; }
  visibility="$(gh api "repos/$repo" | jq -r .visibility)"
  # On the free plan rulesets and secret scanning exist only for public repos (the API answers 403).
  [[ "$visibility" == public ]] || { echo "$repo is $visibility; make it public first (ADR 0016)" >&2; exit 1; }
  existing="$(gh api "repos/$repo/rulesets?includes_parents=false")"
fi

upsert_ruleset "$main_ruleset"
[[ "$kind" == factory ]] && upsert_ruleset "$tag_ruleset"
send PATCH "repos/$repo" "$security"
send PUT "repos/$repo/vulnerability-alerts"
send PUT "repos/$repo/automated-security-fixes"
send PUT "repos/$repo/private-vulnerability-reporting"
send PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" '{"approval_policy": "all_external_contributors"}'
send PUT "repos/$repo/actions/permissions/workflow" "$workflow"
send PATCH "repos/$repo/code-scanning/default-setup" "$codeql"
(( dry )) || echo "$repo: guardrails applied ($kind)"
