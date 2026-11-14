#!/usr/bin/env bash
# Tests .github/scripts/ci-changes.sh and the wiring of .github/workflows/ci.yml (factory ADR 0031): which pull
# requests may skip the build jobs, what the required check says for each mix of job results, and that the
# required check names stay on the jobs the ruleset expects.
#   ci/test-ci-changes.sh        (from the repo root)
set -euo pipefail

s=.github/scripts/ci-changes.sh
[[ -x "$s" ]] || { echo "run from the repo root ($s missing)" >&2; exit 2; }
fails=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }

scope() { # scope <want> <description> <path...>
  local want="$1" what="$2" got; shift 2
  got="$(printf '%s\n' "$@" | "$s" scope)" || got="failed"
  [[ "$got" == "$want" ]] && ok "scope: $what -> $want" || bad "scope: $what -> $got, want $want"
}
scope docs "a roadmap change"                 docs/ROADMAP.md
scope docs "an ADR and a plan"                docs/factory-adr/0031-x.md docs/plans/y.md
scope docs "a root Markdown file"             README.md
scope docs "docs and root Markdown"           docs/ONBOARDING.md SECURITY.md
scope docs "a non-Markdown file under docs/"  docs/diagram.svg
scope full "a script"                         ci/check-docs.sh
scope full "a workflow"                       .github/workflows/ci.yml
scope full "docs and code mixed"              docs/ROADMAP.md plugins/java-pipeline/templates/skeleton/pom.xml
scope full "a skill's Markdown (it changes behaviour)" plugins/java-pipeline/skills/intake/SKILL.md
scope full "a plugin's README"                plugins/java-pipeline/README.md
scope full "Markdown in another folder"       parents/factory-parent/CHANGELOG.md
scope full "a path that only looks like docs" docs-old/x.md
scope full "a root file that isn't Markdown"  README.md.sh
scope full "a path with a newline trick"      $'docs/a.md\nci/x.sh'
got="$(: | "$s" scope)"; [[ "$got" == full ]] && ok "scope: no paths -> full" || bad "scope: no paths -> $got"
got="$(printf '\n\n' | "$s" scope)"; [[ "$got" == full ]] && ok "scope: blank lines only -> full" || bad "scope: blank lines -> $got"

heavy="templates new-project postgres resource-server build-rules"
results() { # results <changes> <scripts> <heavy result>
  printf 'changes %s\nscripts %s\n' "$1" "$2"; local j; for j in $heavy; do echo "$j $3"; done
}
passes() { if SCOPE="$2" RESULTS="$3" "$s" verdict >/dev/null 2>&1; then ok "verdict: $1"; else bad "verdict: $1 (it failed)"; fi; }
refuses() { if SCOPE="$2" RESULTS="$3" "$s" verdict >/dev/null 2>&1; then bad "verdict: $1 (it passed)"; else ok "verdict: $1"; fi; }
passes  "full run, everything green"                       full "$(results success success success)"
passes  "docs-only run, build jobs skipped"                docs "$(results success success skipped)"
passes  "docs-only scope but the build jobs ran green"     docs "$(results success success success)"
refuses "full run with the build jobs skipped"             full "$(results success success skipped)"
refuses "a failed build job"                               full "$(results success success failure)"
refuses "a cancelled build job"                            full "$(results success success cancelled)"
refuses "one build job failed, the rest green"             full "$(results success success success | sed 's/^postgres success/postgres failure/')"
refuses "docs-only run with failed scripts"                docs "$(results success failure skipped)"
refuses "docs-only run with skipped scripts"               docs "$(results success skipped skipped)"
refuses "the changes job failed"                           docs "$(results failure success skipped)"
refuses "no scope (the changes job gave none)"             ""   "$(results success success skipped)"
refuses "an unknown scope"                                 none "$(results success success success)"
refuses "a job missing from the results"                   full "$(results success success success | grep -v '^build-rules ')"
refuses "no results"                                       full ""

# --- the workflow
wf=.github/workflows/ci.yml
job() { awk -v j="$1" '$0 ~ "^  "j":$"{on=1; next} /^  [a-z][a-z-]*:$/{on=0} on' "$wf"; }
names="$(sed -n 's/^    name: //p' "$wf" | sort | paste -sd'|')"
[[ "$names" == "Kubernetes manifests render and match the schemas|Template builds and new-project works" ]] \
  && ok "only the two required checks carry a name" || bad "named jobs: $names"
for j in $heavy; do
  body="$(job "$j")"
  grep -qF "needs: changes" <<<"$body" && grep -qF "if: needs.changes.outputs.scope == 'full'" <<<"$body" \
    && ok "job '$j' runs only on a full scope" || bad "job '$j' lacks the scope condition"
done
body="$(job scripts)"
[[ -n "$body" ]] && ! grep -q '^    if:' <<<"$body" && ok "job 'scripts' always runs" || bad "job 'scripts' is missing or conditional"
grep -qF 'ci/test-ci-changes.sh' <<<"$body" && grep -qF 'ci/check-docs.sh' <<<"$body" && ok "scripts runs this test and the docs check" || bad "scripts lacks this test or the docs check"
body="$(job template)"
grep -qF 'if: always()' <<<"$body" && ok "the required check reports even when a job failed or was skipped" || bad "template job lacks if: always()"
for j in changes scripts $heavy; do
  grep -qE "needs: \[.*\b$j\b.*\]" <<<"$body" && grep -qF "$j \${{ needs.$j.result }}" <<<"$body" \
    && ok "the required check waits for '$j' and reads its result" || bad "the required check ignores '$j'"
done
grep -qF 'ci-changes.sh verdict' <<<"$body" && ok "the required check is the verdict" || bad "template job doesn't run the verdict"
body="$(job changes)"
grep -qF -- '--no-renames' <<<"$body" && ok "a rename lists both paths" || bad "changes doesn't pass --no-renames"
grep -qF "github.event_name == 'pull_request'" <<<"$body" || grep -qF 'EVENT' <<<"$body" && ok "only a pull request can be docs-only" || bad "changes doesn't look at the event"

[[ $fails -eq 0 ]] && echo "ci changes tests: OK" || echo "ci changes tests: FAILED"
exit $fails
