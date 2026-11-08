#!/usr/bin/env bash
# Tests ci/protect-repo.sh (factory ADR 0016) without touching GitHub: the --dry-run requests are checked with jq
# against the guardrails the owner approved, the required check names against the real workflow jobs, and the
# apply path against a fake `gh` (refuses a private repo; creates a missing ruleset, updates an existing one).
#   ci/test-protect-repo.sh        (from the repo root; needs jq)
set -euo pipefail

[[ -f ci/protect-repo.sh ]] || { echo "run from the repo root" >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/protect-repo-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0

ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }
check() { # check <description> <jq filter that must be true> <file>
  if jq -e -s "$2" "$3" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi
}

# A fake gh: logs every call; answers the two reads protect-repo.sh makes. FAKE_VISIBILITY and FAKE_RULESETS
# set the answers.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
log="$FAKE_GH_LOG"
if [[ " $* " == *" --method "* ]]; then
  printf '%s\n' "$*" >> "$log"
  [[ " $* " == *" --input - "* ]] && { cat >> "$log"; echo >> "$log"; }
  echo '{}'
  exit 0
fi
printf 'READ %s\n' "$*" >> "$log"
case "$*" in
  "api repos/acme/demo") printf '{"visibility":"%s"}\n' "$FAKE_VISIBILITY" ;;
  "api repos/acme/demo/rulesets?includes_parents=false") printf '%s\n' "$FAKE_RULESETS" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$work/bin/gh"
export FAKE_GH_LOG="$work/gh.log"

# --- usage
for args in "" "acme/demo" "acme/demo other" "not-a-repo factory"; do
  # shellcheck disable=SC2086
  if ci/protect-repo.sh $args >/dev/null 2>&1; then bad "usage error for '$args'"; else ok "usage error for '$args'"; fi
done

# --- dry run makes no gh calls
: > "$FAKE_GH_LOG"
PATH="$work/bin:$PATH" ci/protect-repo.sh --dry-run acme/demo factory > "$work/factory.jsonl"
PATH="$work/bin:$PATH" ci/protect-repo.sh --dry-run acme/demo service > "$work/service.jsonl"
if [[ -s "$FAKE_GH_LOG" ]]; then bad "dry run calls gh"; else ok "dry run makes no gh calls"; fi

# --- required check names are real job names (they're what GitHub reports as the status context)
mapfile -t factory_jobs < <(sed -n 's/^    name: //p' .github/workflows/ci.yml)
factory_ctx="$(jq -c -s '[.[] | select(.name == "main") | .body.rules[] | select(.type == "required_status_checks")
  | .parameters.required_status_checks[].context] | sort' "$work/factory.jsonl")"
want="$(printf '%s\n' "${factory_jobs[@]}" | jq -R . | jq -c -s 'sort')"
if [[ "$factory_ctx" == "$want" ]]; then ok "factory checks = factory CI job names ($want)"; else
  bad "factory checks $factory_ctx != factory CI job names $want"; fi
for t in plugins/java-pipeline/templates/*/; do
  for job in verify manifests; do
    if grep -q "^  $job:$" "$t.github/workflows/ci.yml" && ! sed -n "/^  $job:\$/,/^  [a-z]/p" "$t.github/workflows/ci.yml" | grep -q '^    name:'; then
      ok "template $(basename "$t") has unnamed job '$job'"
    else
      bad "template $(basename "$t") job '$job' missing or renamed (service required checks would never report)"
    fi
  done
done

# --- the main-branch ruleset, both kinds
for kind in factory service; do
  f="$work/$kind.jsonl"
  check "$kind: one main ruleset on the default branch, active" \
    '[.[] | select(.method == "UPSERT-RULESET" and .name == "main")] | length == 1 and
     (.[0].body | .target == "branch" and .enforcement == "active"
       and .conditions.ref_name.include == ["~DEFAULT_BRANCH"])' "$f"
  check "$kind: PR required with 0 approvals; no deletion or force push" \
    '[.[] | select(.name == "main") | .body.rules[]] as $r
     | ([$r[].type] | sort) == ["deletion", "non_fast_forward", "pull_request", "required_status_checks"]
       and ($r[] | select(.type == "pull_request") | .parameters.required_approving_review_count == 0)' "$f"
  check "$kind: required checks are strict (branch up to date) and from GitHub Actions" \
    '[.[] | select(.name == "main") | .body.rules[] | select(.type == "required_status_checks") | .parameters]
     | .[0] | .strict_required_status_checks_policy == true
       and (.required_status_checks | length > 0 and all(.integration_id == 15368))' "$f"
  check "$kind: only repository admins bypass, and only through a PR" \
    '[.[] | select(.name == "main") | .body.bypass_actors] == [[{"actor_id": 5, "actor_type": "RepositoryRole",
      "bypass_mode": "pull_request"}]]' "$f"
  check "$kind: secret scanning and push protection on" \
    'any(.[]; .method == "PATCH" and .path == "repos/acme/demo"
       and .body.security_and_analysis.secret_scanning.status == "enabled"
       and .body.security_and_analysis.secret_scanning_push_protection.status == "enabled")' "$f"
  for p in vulnerability-alerts automated-security-fixes private-vulnerability-reporting; do
    check "$kind: PUT $p" "any(.[]; .method == \"PUT\" and .path == \"repos/acme/demo/$p\")" "$f"
  done
  check "$kind: CodeQL default setup for Java and Actions" \
    'any(.[]; .path == "repos/acme/demo/code-scanning/default-setup" and .body.state == "configured"
       and (.body.languages | sort) == ["actions", "java-kotlin"])' "$f"
  check "$kind: fork PRs from every outside contributor need approval" \
    'any(.[]; .path == "repos/acme/demo/actions/permissions/fork-pr-contributor-approval"
       and .body.approval_policy == "all_external_contributors")' "$f"
  check "$kind: workflow token read-only by default" \
    'any(.[]; .path == "repos/acme/demo/actions/permissions/workflow"
       and .body.default_workflow_permissions == "read")' "$f"
done
check "service: required checks verify + manifests" \
  '[.[] | select(.name == "main") | .body.rules[] | select(.type == "required_status_checks")
    | .parameters.required_status_checks[].context] | sort == ["manifests", "verify"]' "$work/service.jsonl"

# --- release tags: factory only
check "factory: release tags can't be updated or deleted, by anyone" \
  '[.[] | select(.name == "release tags") | .body] | length == 1 and (.[0] | .target == "tag"
     and (.conditions.ref_name.include | sort) == ["refs/tags/factory-parent-v*", "refs/tags/java-pipeline-v*"]
     and ([.rules[].type] | sort) == ["deletion", "non_fast_forward", "update"] and .bypass_actors == [])' \
  "$work/factory.jsonl"
check "factory: Actions may open PRs (base-image.yml)" \
  'any(.[]; .path == "repos/acme/demo/actions/permissions/workflow" and .body.can_approve_pull_request_reviews == true)' \
  "$work/factory.jsonl"
check "service: no tag ruleset" '[.[] | select(.name == "release tags")] | length == 0' "$work/service.jsonl"

# --- apply, against the fake gh
: > "$FAKE_GH_LOG"
if FAKE_VISIBILITY=private FAKE_RULESETS='[]' PATH="$work/bin:$PATH" ci/protect-repo.sh acme/demo service \
    >/dev/null 2>&1; then bad "private repo refused"; else
  if grep -q -- '--method' "$FAKE_GH_LOG"; then bad "private repo: nothing written"; else ok "private repo refused, nothing written"; fi
fi

: > "$FAKE_GH_LOG"
FAKE_VISIBILITY=public FAKE_RULESETS='[]' PATH="$work/bin:$PATH" ci/protect-repo.sh acme/demo factory >/dev/null
if grep -q -- '--method POST repos/acme/demo/rulesets' "$FAKE_GH_LOG" \
   && [[ "$(grep -c -- '--method POST repos/acme/demo/rulesets' "$FAKE_GH_LOG")" -eq 2 ]]; then
  ok "missing rulesets are created (POST x2)"
else bad "missing rulesets are created (POST x2)"; sed 's/^/    /' "$FAKE_GH_LOG"; fi

: > "$FAKE_GH_LOG"
FAKE_VISIBILITY=public FAKE_RULESETS='[{"id":11,"name":"main"},{"id":12,"name":"release tags"},{"id":13,"name":"other"}]' \
  PATH="$work/bin:$PATH" ci/protect-repo.sh acme/demo factory >/dev/null
if grep -q -- '--method PUT repos/acme/demo/rulesets/11' "$FAKE_GH_LOG" \
   && grep -q -- '--method PUT repos/acme/demo/rulesets/12' "$FAKE_GH_LOG" \
   && ! grep -q -- 'rulesets/13' "$FAKE_GH_LOG" && ! grep -q -- '--method POST repos/acme/demo/rulesets' "$FAKE_GH_LOG"; then
  ok "existing rulesets are updated by name (PUT), others untouched"
else bad "existing rulesets are updated by name (PUT), others untouched"; sed 's/^/    /' "$FAKE_GH_LOG"; fi

# CodeQL goes last: enabling it starts a scan of the default branch.
if [[ "$(grep -- '--method' "$FAKE_GH_LOG" | tail -1)" == *"code-scanning/default-setup"* ]]; then
  ok "CodeQL default setup is the last write"; else bad "CodeQL default setup is the last write"; fi

exit "$fails"
