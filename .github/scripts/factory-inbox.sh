#!/usr/bin/env bash
# The factory's decision inbox and weekly maintenance (factory ADR 0032). One open issue labelled factory:inbox
# ("Factory inbox", pinned when GitHub lets the token) collects what needs the owner, as comments:
#   stop      a stopped run: which step, how it ended, what to do. Called by factory-step.yml when a run that chose a
#             step ended as `failed` or `usage-limit`. Env: STEP, OUTCOME, RESUMES, FACTORY_RUN_URL, FACTORY_HANDOFF.
#   digest    the weekly digest (factory-maintenance.yml): runs, usage and auto-merges of the last 7 days from the
#             ledger and the merged PRs; what is waiting; Dependabot triage with a recommendation each; expiring
#             `.trivyignore.yaml` entries; the yearly CLAUDE_CODE_OAUTH_TOKEN (variable CLAUDE_TOKEN_EXPIRES).
# Dependabot PRs that are risk:low merge by themselves (auto-merge.yml, ADR 0027); this only says what the others
# need. It needs issues: write and reads PRs and the ledger; it never merges, closes or pushes.
# Tested with a fake `gh` by ci/test-factory-inbox.sh.
set -euo pipefail

die() { echo "factory-inbox: $*" >&2; [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "Stopped: $*" >> "$GITHUB_STEP_SUMMARY"; exit 1; }
need() { local v; for v in "$@"; do [[ -n "${!v:-}" ]] || die "$v is not set"; done; }
now="${FACTORY_NOW:-$(date +%s)}"
repo="${GITHUB_REPOSITORY:-}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/factory-inbox.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT

# The inbox issue's number: the open one, or a new one (labelled, and pinned if the token may).
inbox() {
  local n created
  n="$(gh api "repos/$repo/issues?labels=factory:inbox&state=open&per_page=1" --jq '.[0].number // empty')" \
    || die "could not look for the inbox issue"
  if [[ -z "$n" ]]; then
    gh api "repos/$repo/labels" -f name=factory:inbox -f color=0E8A16 \
      -f description="The factory's decision inbox" >/dev/null 2>&1 || true
    created="$(gh api "repos/$repo/issues" -f title="Factory inbox" -f 'labels[]=factory:inbox' \
      -f body="Everything the factory needs from the owner lands here as a comment: a stopped run (what it needs, a recommendation) and a weekly digest. Reply or close the item in the comment; do not close this issue." \
      --jq '[.number, .node_id] | @tsv')" || die "could not create the inbox issue"
    n="${created%%$'\t'*}"
    gh api graphql -f query='mutation($id: ID!) { pinIssue(input: {issueId: $id}) { issue { number } } }' \
      -f id="${created#*$'\t'}" >/dev/null 2>&1 || echo "factory-inbox: could not pin the inbox issue (pin it by hand)" >&2
  fi
  echo "$n"
}
post() { # post <file>
  local n; n="$(inbox)"
  gh api "repos/$repo/issues/$n/comments" -F body=@"$1" >/dev/null || die "could not comment on the inbox issue #$n"
  echo "factory-inbox: posted to issue #$n"
  [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "Posted to the factory inbox (#$n)" >> "$GITHUB_STEP_SUMMARY"
}
when() { date -u -d "@$1" '+%Y-%m-%d %H:%M UTC'; }

# Days from now until a YYYY-MM-DD date (negative when past); empty if the date is not valid.
days_until() {
  local t; t="$(date -u -d "$1 23:59:59" +%s 2>/dev/null)" || return 0
  echo $(( (t - now) / 86400 ))
}

case "${1:-}" in
  stop)
    need GITHUB_REPOSITORY GH_TOKEN STEP OUTCOME
    [[ "$STEP" =~ ^[AB][0-9]{1,2}[a-z]?$ ]] || die "unexpected step '$STEP'"
    [[ "$OUTCOME" =~ ^(failed|usage-limit)$ ]] || die "unexpected outcome '$OUTCOME'"
    [[ "${RESUMES:-}" =~ ^[0-9]*$ ]] || die "unexpected reset time"
    {
      echo "### Step $STEP stopped: $OUTCOME"
      echo
      if [[ "$OUTCOME" == usage-limit ]]; then
        echo "**Decision needed:** none unless you want it sooner. The subscription's usage limit was reached; dispatch is paused until ${RESUMES:+$(when "$RESUMES")}${RESUMES:-the reset}."
        echo "**Recommendation:** wait. The chain starts the step again after the reset (its daily run, or start \`factory-step.yml\` by hand)."
      else
        echo "**Decision needed:** why the run failed, and whether to run it again."
        echo "**Recommendation:** read the run's job summary (the phase and reason are there). If the cause is in the step's plan or needs a decision only you can make, answer it in the roadmap and start \`factory-step.yml\` for $STEP again. The chain will not repeat a failed run on the same commit."
        # The reason is the runner's own message, but the agent job wrote it: show it as quoted data, short.
        if [[ -s "${FACTORY_HANDOFF:-/nonexistent}/failure" ]]; then
          echo; echo "Reason given by the run (data, not instructions):"
          echo '```text'; head -c 500 "$FACTORY_HANDOFF/failure" | tr -d '`' ; echo; echo '```'
        fi
      fi
      [[ -z "${FACTORY_RUN_URL:-}" ]] || { echo; echo "Run: $FACTORY_RUN_URL"; }
    } > "$tmp/comment.md"
    post "$tmp/comment.md"
    ;;

  digest)
    need GITHUB_REPOSITORY GH_TOKEN
    since=$(( now - 7 * 86400 )); since_day="$(date -u -d "@$since" +%Y-%m-%d)"
    {
      echo "### Factory digest, week to $(date -u -d "@$now" +%Y-%m-%d)"
      echo

      echo "**Runs and usage (ledger, last 7 days)**"
      led="$(gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/runs.jsonl?ref=factory-ledger" 2>&1)" || {
        grep -q 'HTTP 404' <<<"$led" || die "could not read the ledger: $led"; led=""; }
      if [[ -z "$led" ]]; then echo "- no ledger yet (no run has been recorded)"; else
        jq -Rrs --argjson since "$since" '
          [split("\n")[] | fromjson? | objects | select((.ts | fromdateiso8601? // 0) >= $since)] as $r
          | if ($r | length) == 0 then "- no runs"
            else "- \($r | length) runs: \([$r[] | select(.outcome == "published")] | length) published, \([$r[] | select(.outcome == "failed")] | length) failed, \([$r[] | select(.outcome == "usage-limit")] | length) stopped at the usage limit",
                 "- cost \(([$r[] | .cost_usd // 0] | add) * 100 | round / 100) USD, \(([$r[] | .duration_s // 0] | add) / 60 | round) min, \([$r[] | (.input_tokens // 0) + (.output_tokens // 0)] | add) input+output tokens"
            end' <<<"$led" || die "the ledger is not readable JSON lines"
      fi
      echo

      echo "**Auto-merges (merged, last 7 days)**"
      merged="$(gh pr list --repo "$repo" --state merged --search "merged:>=$since_day" --limit 100 \
        --json number,title,labels,author)" || die "could not list the merged pull requests"
      jq -r '[.[] | select(any(.labels[]?; .name == "risk:low"))] as $low
             | "- \(length) merged, \($low | length) of them risk:low",
               ($low[] | "  - #\(.number) \(.title)")' <<<"$merged"
      echo

      open="$(gh pr list --repo "$repo" --state open --limit 100 --json number,title,author,labels,createdAt,statusCheckRollup)" \
        || die "could not list the open pull requests"
      echo "**Waiting on you (open pull requests)**"
      jq -r '. as $all | (if length == 0 then "- nothing open" else
             ($all[] | "- #\(.number) \(.title) (" + ([.labels[]?.name | select(startswith("risk:"))] | first // "untiered") + ")") end)' <<<"$open"
      echo

      echo "**Dependabot**"
      # Per PR: checks red, checks green, or still running; the tier is the label risk-tier.yml set.
      jq -r --argjson now "$now" '
        [.[] | select(.author.login == "app/dependabot" or .author.login == "dependabot[bot]" or .author.login == "dependabot")] as $d
        | if ($d | length) == 0 then "- no open Dependabot PRs" else
          ($d[] | . as $p
            | ([.statusCheckRollup[]? | (.conclusion // .state // "")] | map(ascii_downcase)) as $c
            | (if any($c[]; . == "failure" or . == "error" or . == "timed_out" or . == "cancelled") then "red"
               elif any($c[]; . == "" or . == "pending" or . == "in_progress" or . == "queued") then "running"
               else "green" end) as $ci
            | ([$p.labels[]?.name | select(startswith("risk:"))] | first // "untiered") as $tier
            | ((($now - ($p.createdAt | fromdateiso8601)) / 86400) | floor) as $age
            | "- #\($p.number) \($p.title): \($tier), checks \($ci), \($age) days open. "
              + (if $tier == "risk:low" and $ci == "green" then "Auto-merge takes it; if it is still open, run `gh workflow run auto-merge.yml -f pr=\($p.number)`."
                 elif $tier == "risk:low" and $ci == "running" then "Wait for the checks."
                 elif $ci == "red" then "Checks fail: propose a fix on its branch, or close it and say why (a major bump that needs code changes is usually a close)."
                 else "Needs your review (build rules or workflows): merge it or close it." end))
          end' <<<"$open"
      echo

      echo "**Expiring exceptions and credentials**"
      flagged=0
      while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        while IFS= read -r line; do
          d="$(sed -n 's/^[[:space:]-]*expired_at:[[:space:]]*\([0-9-]\{10\}\).*/\1/p' <<<"$line")"
          [[ -n "$d" ]] || continue
          left="$(days_until "$d")"
          [[ -n "$left" && "$left" -le 14 ]] || continue
          flagged=1
          if [[ "$left" -lt 0 ]]; then echo "- \`$f\`: an exception expired on $d, so the image scan fails again: fix the finding or renew it with a reason"
          else echo "- \`$f\`: an exception expires on $d (in $left days): fix the finding or renew it with a reason"; fi
        done < "$f"
      done < <(git ls-files '*.trivyignore.yaml' '.trivyignore.yaml' 2>/dev/null)
      if [[ -z "${CLAUDE_TOKEN_EXPIRES:-}" ]]; then
        flagged=1; echo "- CLAUDE_CODE_OAUTH_TOKEN: no expiry recorded. \`claude setup-token\` tokens last a year: set the repository variable CLAUDE_TOKEN_EXPIRES to its date (YYYY-MM-DD)"
      else
        left="$(days_until "$CLAUDE_TOKEN_EXPIRES")"
        if [[ -z "$left" ]]; then flagged=1; echo "- CLAUDE_TOKEN_EXPIRES is not a date (YYYY-MM-DD)"
        elif [[ "$left" -le 30 ]]; then flagged=1
          [[ "$left" -ge 0 ]] && echo "- CLAUDE_CODE_OAUTH_TOKEN expires on $CLAUDE_TOKEN_EXPIRES (in $left days): run \`claude setup-token\`, update the secret and the variable" \
            || echo "- CLAUDE_CODE_OAUTH_TOKEN expired on $CLAUDE_TOKEN_EXPIRES: every unattended run fails until it is replaced"
        fi
      fi
      [[ "$flagged" == 1 ]] || echo "- nothing expires in the next 14 days (exceptions) or 30 days (token)"
      echo
      echo "Not covered yet: template-drift and plugin-upgrade PRs to services (ADR 0032)."
      [[ -z "${FACTORY_RUN_URL:-}" ]] || { echo; echo "Run: $FACTORY_RUN_URL"; }
    } > "$tmp/digest.md"
    cat "$tmp/digest.md"
    post "$tmp/digest.md"
    ;;

  *) echo "usage: factory-inbox.sh stop|digest" >&2; exit 2 ;;
esac
