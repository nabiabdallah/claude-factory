#!/usr/bin/env bash
# Tests .github/scripts/factory-inbox.sh (factory ADR 0032) with a fake `gh` that records its calls and keeps the
# comments it is given. No GitHub involved.
#   ci/test-factory-inbox.sh        (from the repo root)
set -euo pipefail

[[ -x .github/scripts/factory-inbox.sh ]] || { echo "run from the repo root" >&2; exit 2; }
root="$PWD"
work="$(mktemp -d "${TMPDIR:-/tmp}/factory-inbox-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }

mkdir -p "$work/bin" "$work/gh" "$work/repo/svc"
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH/calls"
args=("$@")
for a in "$@"; do
  if [[ "$a" == body=@* ]]; then cat "${a#body=@}" >> "$FAKE_GH/comments"; echo "=====" >> "$FAKE_GH/comments"; fi
done
case "$*" in
  "api repos/acme/factory/issues?labels=factory:inbox&state=open&per_page=1 "*)
    [[ -f "$FAKE_GH/inbox-exists" ]] && echo 7 || true ;;
  "api repos/acme/factory/labels "*) echo '{}' ;;
  "api repos/acme/factory/issues -f title=Factory inbox "*) touch "$FAKE_GH/inbox-exists"; printf '7\tNODE\n' ;;
  "api graphql "*) [[ ! -f "$FAKE_GH/pin-fails" ]] || exit 1; echo '{}' ;;
  "api repos/acme/factory/issues/7/comments "*) echo '{}' ;;
  "api -H Accept: application/vnd.github.raw repos/acme/factory/contents/runs.jsonl?ref=factory-ledger")
    [[ ! -f "$FAKE_GH/ledger-fails" ]] || { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }
    cat "$FAKE_GH/ledger" 2>/dev/null || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  "pr list --repo acme/factory --state merged "*) cat "$FAKE_GH/merged" ;;
  "pr list --repo acme/factory --state open "*) cat "$FAKE_GH/open" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" FAKE_GH="$work/gh" GITHUB_REPOSITORY=acme/factory GH_TOKEN=t
unset GITHUB_STEP_SUMMARY FACTORY_RUN_URL FACTORY_HANDOFF CLAUDE_TOKEN_EXPIRES RESUMES 2>/dev/null || true
export FACTORY_NOW=1798000000 # 2026-12-23
inbox() { (cd "$work/repo" && "$root/.github/scripts/factory-inbox.sh" "$@") >"$work/out" 2>&1; }
fresh() { rm -rf "$work/gh"/*; : > "$work/gh/calls"; : > "$work/gh/comments"; echo '[]' > "$work/gh/merged"; echo '[]' > "$work/gh/open"; }
has() { grep -qF -- "$2" "$1"; }
comments() { cat "$work/gh/comments"; }

# --- a stopped run lands in the inbox
fresh
STEP=B7 OUTCOME=failed FACTORY_RUN_URL=https://example.invalid/run/1 inbox stop && ok "stop: a failed run is posted" || bad "stop failed: $(cat "$work/out")"
comments | grep -q 'Step B7 stopped: failed' && comments | grep -q 'Decision needed' && comments | grep -q 'Recommendation' \
  && ok "the comment has a decision and a recommendation" || bad "comment: $(comments)"
comments | grep -q 'example.invalid/run/1' && ok "the comment links the run" || bad "no run link"
grep -q 'title=Factory inbox' "$work/gh/calls" && grep -q 'graphql' "$work/gh/calls" && ok "the inbox issue is created and pinned the first time" || bad "no create/pin: $(cat "$work/gh/calls")"
STEP=B7 OUTCOME=failed inbox stop
[[ "$(grep -c 'title=Factory inbox' "$work/gh/calls")" == 1 ]] && ok "the second stop reuses the inbox issue" || bad "created the inbox twice"

fresh; touch "$work/gh/pin-fails"
STEP=B7 OUTCOME=failed inbox stop && has "$work/out" "could not pin" && ok "a pin that GitHub refuses does not stop the post" || bad "pin failure: $(cat "$work/out")"

fresh; mkdir -p "$work/h"; printf 'the agent stopped with `exit code 7`\n' > "$work/h/failure"
STEP=B7 OUTCOME=failed FACTORY_HANDOFF="$work/h" inbox stop
comments | grep -q 'exit code 7' && ! comments | grep -q '`exit code' && ok "the reason is quoted as data, backticks removed" || bad "reason: $(comments)"

fresh
STEP=B7 OUTCOME=usage-limit RESUMES=4102444800 inbox stop
comments | grep -q 'paused until 2100-01-01' && comments | grep -q 'Recommendation:\*\* wait' && ok "usage-limit: the reset time and 'wait'" || bad "limit comment: $(comments)"
fresh; STEP=B7 OUTCOME=published inbox stop && bad "stop accepted outcome published" || ok "stop refuses an outcome that is not a stop"
fresh; STEP='B7; x' OUTCOME=failed inbox stop && bad "stop accepted a malformed step" || ok "stop refuses a malformed step"
fresh; STEP=B7 OUTCOME=usage-limit RESUMES=abc inbox stop && bad "stop accepted a bad reset time" || ok "stop refuses a bad reset time"

# --- the digest
today=2026-12-23
recent="2026-12-22T10:00:00Z"; old="2026-11-01T10:00:00Z"
fresh
cat > "$work/gh/ledger" <<L
{"ts":"$old","step":"B1","outcome":"published","cost_usd":9,"duration_s":600,"input_tokens":1,"output_tokens":1}
{"ts":"$recent","step":"B6","outcome":"published","cost_usd":2.5,"duration_s":300,"input_tokens":100,"output_tokens":50}
{"ts":"$recent","step":"B7","outcome":"failed","cost_usd":1.25,"duration_s":120,"input_tokens":10,"output_tokens":5}
L
cat > "$work/gh/merged" <<'J'
[{"number":40,"title":"docs: x","labels":[{"name":"risk:low"}],"author":{"login":"app/nabiabdallah-factory-bot"}},
 {"number":41,"title":"feat: y","labels":[{"name":"risk:high"}],"author":{"login":"nabiabdallah"}}]
J
cat > "$work/gh/open" <<J
[{"number":50,"title":"deps: bump a","author":{"login":"app/dependabot"},"labels":[{"name":"risk:low"}],"createdAt":"$recent","statusCheckRollup":[{"conclusion":"SUCCESS"}]},
 {"number":51,"title":"deps: bump b","author":{"login":"app/dependabot"},"labels":[{"name":"risk:low"}],"createdAt":"$recent","statusCheckRollup":[{"conclusion":"FAILURE"}]},
 {"number":52,"title":"ci: bump c","author":{"login":"app/dependabot"},"labels":[{"name":"risk:high"}],"createdAt":"2026-12-01T00:00:00Z","statusCheckRollup":[{"conclusion":"SUCCESS"}]},
 {"number":53,"title":"feat: step","author":{"login":"app/nabiabdallah-factory-bot"},"labels":[{"name":"risk:high"}],"createdAt":"$recent","statusCheckRollup":[]}]
J
mkdir -p "$work/repo" && cd "$work/repo" && git init -q . 2>/dev/null; cd "$root"
printf 'vulnerabilities:\n  - id: CVE-1\n    expired_at: 2026-12-30\n  - id: CVE-2\n    expired_at: 2027-06-01\n  - id: CVE-3\n    expired_at: 2026-12-01\n' > "$work/repo/.trivyignore.yaml"
git -C "$work/repo" add .trivyignore.yaml
CLAUDE_TOKEN_EXPIRES=2027-01-10 FACTORY_RUN_URL=https://example.invalid/run/2 inbox digest && ok "digest: posts" || bad "digest failed: $(cat "$work/out")"
d="$(comments)"
grep -q '2 runs: 1 published, 1 failed, 0 stopped' <<<"$d" && grep -q 'cost 3.75 USD' <<<"$d" && ok "runs and cost count only the last 7 days" || bad "ledger part: $d"
grep -q '2 merged, 1 of them risk:low' <<<"$d" && grep -q '#40 docs: x' <<<"$d" && ok "auto-merges listed" || bad "merged part: $d"
grep -q '#50 .*risk:low, checks green.*Auto-merge takes it' <<<"$d" && ok "Dependabot: low and green is left to auto-merge" || bad "dependabot 50: $d"
grep -q '#51 .*checks red.*propose a fix' <<<"$d" && ok "Dependabot: red gets a fix-or-close recommendation" || bad "dependabot 51: $d"
grep -q '#52 .*risk:high.*Needs your review' <<<"$d" && ok "Dependabot: high needs the owner" || bad "dependabot 52: $d"
grep -q '#53 feat: step (risk:high)' <<<"$d" && ! grep -q '#53 .*Dependabot' <<<"$d" && ok "open PRs listed; non-Dependabot not triaged" || bad "waiting: $d"
grep -q 'expires on 2026-12-30 (in 7 days)' <<<"$d" && ok "an exception expiring within 14 days is flagged" || bad "trivy soon: $d"
grep -q 'expired on 2026-12-01' <<<"$d" && ok "an expired exception is flagged" || bad "trivy expired: $d"
! grep -q 2027-06-01 <<<"$d" && ok "a far exception is not flagged" || bad "trivy far flagged"
grep -q 'TOKEN\|CLAUDE_CODE_OAUTH_TOKEN expires on 2027-01-10 (in 18 days)' <<<"$d" && ok "the token expiring within 30 days is flagged" || bad "token: $d"
grep -q 'template-drift' <<<"$d" && ok "the digest says what it does not cover" || bad "no coverage note"

fresh; : > "$work/repo/.trivyignore.yaml"; git -C "$work/repo" add .trivyignore.yaml
CLAUDE_TOKEN_EXPIRES=2027-09-01 inbox digest; d="$(comments)"
grep -q 'no ledger yet' <<<"$d" && grep -q 'no open Dependabot' <<<"$d" && grep -q 'nothing expires' <<<"$d" && ok "digest on a quiet week and no ledger" || bad "quiet: $d"
fresh; inbox digest; comments | grep -q 'no expiry recorded' && ok "an unrecorded token expiry is flagged" || bad "token unset: $(comments)"
fresh; touch "$work/gh/ledger-fails"; inbox digest && bad "digest went on with an unreadable ledger" || { has "$work/out" "could not read the ledger" && ok "digest stops when the ledger can't be read" || bad "ledger error: $(cat "$work/out")"; }

# --- the workflows call it
wf=.github/workflows
grep -q 'factory-inbox.sh stop' $wf/factory-step.yml && grep -q 'factory-inbox.sh digest' $wf/factory-maintenance.yml \
  && ok "workflows call the inbox script" || bad "workflows don't call the script"
awk '/^  inbox:/{on=1} on' $wf/factory-step.yml | grep -q 'issues: write' && ! awk '/^  inbox:/{on=1} on' $wf/factory-step.yml | grep -q 'FACTORY_APP_KEY' \
  && ok "the inbox job writes issues with the workflow token, not the App" || bad "inbox job permissions"
grep -q "cron:" $wf/factory-maintenance.yml && ok "the digest is scheduled" || bad "no schedule"

[[ $fails -eq 0 ]] && echo "factory inbox tests: OK" || echo "factory inbox tests: FAILED"
exit $fails
