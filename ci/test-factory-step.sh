#!/usr/bin/env bash
# Tests .github/scripts/factory-step.sh (factory ADR 0022) without GitHub or a Claude credential: `gh` is a fake
# that records its calls, the agent is a stand-in that does what a scenario asks, and the two jobs run in two
# separate clones of a throwaway repo, handing over only the bundle and the report, as in the workflow.
#   ci/test-factory-step.sh        (from the repo root)
set -euo pipefail

[[ -x .github/scripts/factory-step.sh ]] || { echo "run from the repo root" >&2; exit 2; }
root="$PWD"
work="$(mktemp -d "${TMPDIR:-/tmp}/factory-step-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }
g() { git -c user.name=test -c user.email=test@example.invalid "$@"; }

# --- a throwaway factory repo: the runner, the CLI pin it reads, a queue, a test script, the rules file
mkdir -p "$work/seed/.github/scripts" "$work/seed/plugins/java-pipeline/templates/skeleton/.github/scripts" "$work/seed/docs" "$work/seed/ci"
cp .github/scripts/factory-step.sh "$work/seed/.github/scripts/"
echo 'claude_code_version=9.9.9' > "$work/seed/plugins/java-pipeline/templates/skeleton/.github/scripts/factory-run.sh"
cat > "$work/seed/docs/ROADMAP.md" <<'MD'
| # | Step | Gap | Done when |
|---|---|---|---|
| B0 ✅ | Guardrails | x | x |
| B1 (built, awaiting the owner) | Identity | x | x |
| B2 | Steps in Actions | x | x |
| B2a | Runner split | x | x |
| B3 | Provisioning | x | x |
MD
echo 'echo ok' > "$work/seed/ci/test-something.sh"
echo '# rules' > "$work/seed/CLAUDE.md"
git -C "$work/seed" init -q -b main && g -C "$work/seed" add -A && g -C "$work/seed" commit -q -m seed
git clone -q --bare "$work/seed" "$work/remote.git"

mkdir -p "$work/bin" "$work/gh"
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH/calls"
case "$*" in
  "pr list "*) cat "$FAKE_GH/open-prs" 2>/dev/null || true ;;
  "api repos/acme/factory/branches/"*) [[ -f "$FAKE_GH/branch-exists" ]] && echo branch || exit 1 ;;
  "api -H Accept: application/vnd.github.raw repos/acme/factory/contents/runs.jsonl?ref=factory-ledger")
    [[ ! -f "$FAKE_GH/ledger-fails" ]] || { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }
    cat "$FAKE_GH/ledger" 2>/dev/null || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  "api repos/acme/factory/pulls "*) echo "https://github.com/acme/factory/pull/42" ;;
  "api repos/acme/factory/labels "*|"api repos/acme/factory/issues/42/labels "*) echo '{}' ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
SH
cat > "$work/bin/agent" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$FAKE_GH/agent-args"
[[ "${FACTORY_HEADLESS:-}" == 1 && -n "${FACTORY_STEP:-}" ]] || { echo "not headless" >&2; exit 3; }
g() { git -c user.name=agent -c user.email=agent@example.invalid "$@"; }
report() { printf '# feat: step %s\n\nDid the step.\n' "$FACTORY_STEP" > "$FACTORY_REPORT"; }
case "$SCENARIO" in
  ok)          echo x > docs/new.md; g add docs/new.md; g commit -qm "docs: x"; report ;;
  protected)   echo y >> CLAUDE.md; g add CLAUDE.md; g commit -qm "docs: rules"; report ;;
  template-wf) mkdir -p plugins/x/templates/y/.github/workflows; echo a > plugins/x/templates/y/.github/workflows/a.yml
               g add plugins; g commit -qm "ci: template"; report ;;
  delete-test) g rm -q ci/test-something.sh; g commit -qm "drop test"; report ;;
  no-report)   echo x > docs/new.md; g add docs/new.md; g commit -qm "docs: x" ;;
  no-commit)   report ;;
  leftovers)   echo x > docs/new.md; g add docs/new.md; g commit -qm "docs: x"; echo z > stray.txt; report ;;
  crash)       exit 7 ;;
  # What the CLI prints (as JSON) when the subscription's limit is reached; the agent exits non-zero.
  limit)       echo '{"type":"result","is_error":true,"result":"Claude AI usage limit reached|4102444800","total_cost_usd":1.5,"duration_ms":4000}'; exit 1 ;;
  limit-nodate) echo '{"is_error":true,"result":"Claude AI usage limit reached"}'; exit 1 ;;
  # A good run whose report merely talks about usage limits must not count as one.
  talks)       echo x > docs/new.md; g add docs/new.md; g commit -qm "docs: x"; report
               echo '{"is_error":false,"result":"Claude AI usage limit reached|4102444800"}' ;;
  budget)      echo '{"is_error":true,"subtype":"error_max_budget_usd","result":"Reached maximum budget ($25)"}'; exit 1 ;;
  # The agent rewrites the runner so its gate would pass anything: the publish job must not run that copy.
  tamper)      printf '#!/bin/sh\nexit 0\n' > .github/scripts/factory-step.sh; g rm -q ci/test-something.sh
               g add .github/scripts/factory-step.sh; g commit -qm "tamper"; report ;;
  # A step whose work is the runner itself (B6 was one): the file changes, and grows, under the phase that is
  # running it, and its own `pack` no longer fits this run. bash reads a script as it goes, so after the phase it
  # would carry on reading where the old file ended, in the middle of the new one.
  rewrite-runner) { printf '#!/usr/bin/env bash\n'; for _ in $(seq 20000); do echo '(((('; done; } > .github/scripts/factory-step.sh
               g add .github/scripts/factory-step.sh; g commit -qm "feat: a new runner"; report ;;
esac
SH
chmod +x "$work/bin/gh" "$work/bin/agent"
export PATH="$work/bin:$PATH" FAKE_GH="$work/gh" GITHUB_REPOSITORY=acme/factory FACTORY_AGENT_CMD=agent
unset GITHUB_OUTPUT GITHUB_STEP_SUMMARY FACTORY_PAUSED STEP 2>/dev/null || true

n=0
fresh() { # a new agent-job clone and state; resets the fake gh
  n=$((n + 1)); rm -rf "$work/gh"/*; : > "$work/gh/calls"
  git --git-dir="$work/remote.git" branch -q -D factory/step-b2 2>/dev/null || true
  A="$work/a$n" P="$work/p$n" SA="$work/sa$n" SP="$work/sp$n"
  git clone -q "$work/remote.git" "$A"; mkdir -p "$SA" "$SP"
}
run_a() { (cd "$A" && FACTORY_STATE="$SA" .github/scripts/factory-step.sh "$@") >"$work/out" 2>&1; }
# As the workflow's agent job does: the runner is copied out of the checkout before the agent runs, and the
# phases from `agent` on run that copy.
keep() { cp "$A/.github/scripts/factory-step.sh" "$SA.runner.sh"; }
run_k() { (cd "$A" && FACTORY_STATE="$SA" bash "$SA.runner.sh" "$@") >"$work/out" 2>&1; }
# The publish job: a clone of the base, its own trusted runner, the hand-over from the agent job's state.
run_p() {
  [[ -d "$P" ]] || git clone -q "$work/remote.git" "$P"
  (cd "$P" && git checkout -q "$(cat "$SA/base")" && STEP="$(cat "$SA/step")" BRANCH="$(cat "$SA/branch")" \
    BASE="$(cat "$SA/base")" FACTORY_HANDOFF="$SA" FACTORY_STATE="$SP" GH_TOKEN=t FACTORY_PUSH_URL="$work/remote.git" \
    .github/scripts/factory-step.sh "$@") >"$work/out" 2>&1
}
expect_ok() { if "${@:2}"; then ok "$1"; else bad "$1: $(tail -n 3 "$work/out")"; fi; }
expect_fail() { # expect_fail <description> <message part> <command...>
  if "${@:3}"; then bad "$1 (it passed)"; elif grep -qF -- "$2" "$work/out"; then ok "$1"
  else bad "$1: wrong reason: $(tail -n 3 "$work/out")"; fi
}

# --- resolve
fresh; expect_ok "resolve picks the first unfinished step (B2)" run_a resolve
[[ "$(cat "$SA/step")" == B2 && "$(cat "$SA/branch")" == factory/step-b2 ]] && ok "step B2 on factory/step-b2" || bad "step/branch: $(cat "$SA/step") $(cat "$SA/branch")"
fresh; STEP=B3 expect_ok "resolve takes an unfinished step by name" run_a resolve
fresh; STEP=B2a expect_ok "resolve takes a sub-step (B2a)" run_a resolve
[[ "$(cat "$SA/branch")" == factory/step-b2a ]] && ok "sub-step branch factory/step-b2a" || bad "sub-step branch: $(cat "$SA/branch")"
fresh; STEP=B1 expect_fail "resolve refuses a step waiting on the owner" "not an unfinished step" run_a resolve
fresh; STEP=B0 expect_fail "resolve refuses a done step" "not an unfinished step" run_a resolve
fresh; STEP='B2; rm -rf /' expect_fail "resolve refuses a malformed step" "must look like" run_a resolve
fresh; FACTORY_PAUSED=true expect_fail "resolve refuses while paused" "paused" run_a resolve
fresh; echo factory/step-b9 > "$FAKE_GH/open-prs"; expect_fail "resolve refuses while a step PR is open" "one step at a time" run_a resolve
fresh; touch "$FAKE_GH/branch-exists"; expect_fail "resolve refuses an existing branch" "already exists" run_a resolve

# --- agent + pack
for case in "no-report|no report was written" "no-commit|committed nothing" "leftovers|stray.txt"; do
  sc="${case%%|*}" why="${case#*|}"
  fresh; run_a resolve; SCENARIO=$sc run_a agent
  expect_fail "pack refuses: $sc" "$why" run_a pack
done
fresh; run_a resolve; SCENARIO=crash expect_fail "agent: a crashed agent fails the run" "exit code 7" run_a agent
fresh; run_a resolve
( unset FACTORY_AGENT_CMD; cd "$A" && FACTORY_STATE="$SA" .github/scripts/factory-step.sh agent ) >"$work/out" 2>&1 \
  && bad "agent without a credential" || { grep -qF "no Claude credential" "$work/out" && ok "agent refuses without a Claude credential" || bad "agent credential: $(tail -n 2 "$work/out")"; }

# --- the subscription's usage limit
fresh; run_a resolve; SCENARIO=limit expect_ok "agent: a usage limit ends the phase, it is not a failure" run_a agent
[[ "$(cat "$SA/outcome")" == usage-limit && "$(cat "$SA/resumes")" == 4102444800 ]] && ok "outcome usage-limit with the reset time from the message" || bad "outcome: $(cat "$SA/outcome" "$SA/resumes" 2>&1)"
grep -q 'usage limit' "$work/out" && ok "the run says it stopped at the limit" || bad "no usage-limit message: $(cat "$work/out")"
fresh; run_a resolve; SCENARIO=limit-nodate run_a agent
resumes="$(cat "$SA/resumes")"
(( resumes > $(date +%s) + 4 * 3600 && resumes <= $(date +%s) + 5 * 3600 )) && ok "no reset time in the message: pause of 5 hours" || bad "default pause: $resumes"
fresh; run_a resolve; SCENARIO=talks expect_ok "a good run that mentions a usage limit is not a limit run" run_a agent
[[ ! -e "$SA/outcome" ]] && ok "(no outcome file)" || bad "a good run was taken for a limit"
fresh; run_a resolve; SCENARIO=budget expect_fail "the budget guard is a failure, not a usage limit" "exit code 1" run_a agent
# resolve and paused read the ledger: the last record decides
fresh; echo '{"step":"B6","outcome":"usage-limit","resumes_at":4102444800}' > "$FAKE_GH/ledger"
expect_fail "resolve refuses while the last ledger record is a limit still in force" "usage limit was hit" run_a resolve
out="$(cd "$A" && .github/scripts/factory-step.sh paused)"; [[ "$out" == 4102444800 ]] && ok "paused prints the reset time" || bad "paused: '$out'"
fresh; echo '{"step":"B6","outcome":"usage-limit","resumes_at":1000}' > "$FAKE_GH/ledger"
expect_ok "resolve runs once the reset time has passed" run_a resolve
fresh; printf '%s\n' '{"step":"B6","outcome":"usage-limit","resumes_at":4102444800}' '{"step":"B6","outcome":"published"}' > "$FAKE_GH/ledger"
expect_ok "a later run clears the pause" run_a resolve
fresh; printf '%s\n' 'garbage' '{"step":"B6","outcome":"published"}' > "$FAKE_GH/ledger"
expect_ok "a line that is not JSON in the ledger is skipped" run_a resolve
fresh; touch "$FAKE_GH/ledger-fails"; expect_fail "resolve stops when the ledger can't be read (not a 404)" "could not read the ledger" run_a resolve
fresh; expect_ok "no ledger branch yet (404) is not a pause" run_a resolve

# --- the ledger job: appends to runs.jsonl on the factory-ledger branch
L="$work/remote.git"
ledger() { (cd "$P" && STEP="$1" OUTCOME="$2" RESUMES="${3:-}" FACTORY_HANDOFF="$work/handoff" FACTORY_STATE="$SP" GH_TOKEN=t \
  FACTORY_PUSH_URL="$L" GITHUB_RUN_ID=77 .github/scripts/factory-step.sh ledger) >"$work/out" 2>&1; }
fresh; git clone -q "$work/remote.git" "$P"
mkdir -p "$work/handoff"
echo '{"total_cost_usd":1.25,"duration_ms":61500,"num_turns":9,"usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":"evil"},"result":"x"}' > "$work/handoff/agent.json"
expect_ok "ledger creates the branch on the first record" ledger B6 published
git --git-dir="$L" cat-file -p factory-ledger:runs.jsonl > "$work/runs" 2>/dev/null && ok "factory-ledger has runs.jsonl" || bad "no ledger branch"
[[ "$(git --git-dir="$L" rev-list --count factory-ledger)" == 1 && -z "$(git --git-dir="$L" ls-tree -r --name-only factory-ledger | grep -v '^runs.jsonl$')" ]] \
  && ok "the branch holds only runs.jsonl (orphan)" || bad "ledger branch carries more than the ledger"
jq -e '.step == "B6" and .outcome == "published" and .run == "77" and .cost_usd == 1.25 and .duration_s == 62 and .turns == 9 and .input_tokens == 10 and .output_tokens == 20 and .cache_read_tokens == 30 and .cache_creation_tokens == 0 and .resumes_at == null' "$work/runs" >/dev/null \
  && ok "the record has outcome, duration, cost and tokens (a non-number counts as 0)" || bad "record: $(cat "$work/runs")"
rm "$work/handoff/agent.json"
expect_ok "ledger appends a second record (no result: zeros)" ledger B7 usage-limit 4102444800
git --git-dir="$L" cat-file -p factory-ledger:runs.jsonl > "$work/runs"
[[ "$(wc -l < "$work/runs")" == 2 ]] && jq -se '.[1].outcome == "usage-limit" and .[1].resumes_at == 4102444800 and .[1].cost_usd == 0' "$work/runs" >/dev/null \
  && ok "records accumulate, the limit record carries its reset time" || bad "ledger: $(cat "$work/runs")"
expect_fail "ledger refuses an outcome it does not know" "unexpected outcome" ledger B6 merged
expect_fail "ledger refuses a limit record without a reset time" "needs its reset time" ledger B6 usage-limit
expect_fail "ledger refuses a malformed step" "unexpected step" ledger 'B6;x' published
# What the chain and resolve read back: the ledger above ends on a limit still in force.
git --git-dir="$L" cat-file -p factory-ledger:runs.jsonl > "$FAKE_GH/ledger"
expect_fail "after that record, resolve pauses" "usage limit was hit" run_a resolve
git --git-dir="$L" branch -q -D factory-ledger

# --- the workflow wires the ledger and the limit
wf="$root/.github/workflows/factory-step.yml"
grep -q "if: steps.run.outputs.outcome != 'usage-limit'" "$wf" && ok "factory-step.yml skips pack on a usage limit" || bad "pack not skipped on a usage limit"
grep -q "if: needs.agent.outputs.outcome != 'usage-limit'" "$wf" && ok "factory-step.yml skips publish on a usage limit" || bad "publish not skipped on a usage limit"
awk '/^  ledger:/{on=1} on' "$wf" | grep -q 'factory-step.sh ledger' && ok "factory-step.yml has a ledger job" || bad "no ledger job"

# --- the happy path, end to end
fresh; run_a resolve; SCENARIO=ok run_a agent; expect_ok "pack: ok" run_a pack
grep -qF "continue with step B2" "$FAKE_GH/agent-args" && ok "the prompt names the step" || bad "prompt: $(cat "$FAKE_GH/agent-args")"
expect_ok "gate passes a normal step" run_p gate
[[ ! -s "$SP/protected" ]] && ok "normal step is not risk:high" || bad "normal step flagged: $(cat "$SP/protected")"
expect_ok "publish opens the PR" run_p publish
git --git-dir="$work/remote.git" rev-parse -q --verify refs/heads/factory/step-b2 >/dev/null && ok "branch pushed" || bad "branch not pushed"
grep -q 'api repos/acme/factory/pulls -f title=feat: step B2 -f head=factory/step-b2 -f base=main' "$FAKE_GH/calls" && ok "PR title from the report" || bad "PR call: $(grep pulls "$FAKE_GH/calls")"
! grep -q 'labels' "$FAKE_GH/calls" && ok "no risk label on a normal step" || bad "label set on a normal step"

# --- protected files: published, labelled risk:high
fresh; run_a resolve; SCENARIO=protected run_a agent; run_a pack
expect_ok "gate passes a protected change" run_p gate
grep -qx CLAUDE.md "$SP/protected" && ok "CLAUDE.md flagged as protected" || bad "CLAUDE.md not flagged"
expect_ok "publish: protected" run_p publish
grep -q 'issues/42/labels -f labels\[\]=risk:high' "$FAKE_GH/calls" && ok "PR labelled risk:high" || bad "no risk:high label"
grep -qF 'risk:high' "$SP/pr-body.md" && ok "PR body lists the protected files" || bad "PR body lacks risk note"

fresh; run_a resolve; SCENARIO=template-wf run_a agent; run_a pack; run_p gate
grep -qx plugins/x/templates/y/.github/workflows/a.yml "$SP/protected" && ok "a template's workflow is protected too" || bad "template workflow not flagged"

# --- refusals in the publish job
fresh; run_a resolve; SCENARIO=delete-test run_a agent; run_a pack
expect_fail "gate refuses a deleted test" "deleted tests" run_p gate
# The tampered pack does nothing; the agent hands over a bundle by hand instead. The publish job must still run
# the base's runner, which sees the deleted test.
fresh; run_a resolve; SCENARIO=tamper run_a agent; run_a pack || true
(cd "$A" && git bundle create "$SA/agent.bundle" refs/heads/factory/step-b2 "^$(cat "$SA/base")" >/dev/null 2>&1)
expect_fail "gate runs the base's runner, not the agent's rewritten one" "deleted tests" run_p gate
# --- a step that rewrites the runner (the B6 runs of 2026-11-13 failed here)
fresh; run_a resolve
SCENARIO=rewrite-runner expect_ok "agent: the phase finishes although the agent rewrote the runner under it" run_a agent
fresh; run_a resolve; keep
SCENARIO=rewrite-runner expect_ok "agent, from the kept runner" run_k agent
expect_ok "pack is the kept runner's, not the agent's rewritten one" run_k pack
[[ -s "$SA/agent.bundle" ]] && ok "the rewritten runner is handed over as commits" || bad "no bundle"
expect_ok "gate passes a step that changes the runner" run_p gate
grep -qx .github/scripts/factory-step.sh "$SP/protected" && ok "the runner change is flagged risk:high" || bad "runner change not flagged"
wf="$root/.github/workflows/factory-step.yml"
kept_line="$(grep -n 'cp .github/scripts/factory-step.sh "$RUNNER_TEMP/factory-step.sh"' "$wf" | head -n 1 | cut -d: -f1 || true)"
resolve_line="$(grep -n 'factory-step.sh resolve' "$wf" | head -n 1 | cut -d: -f1)"
[[ -n "$kept_line" && "$kept_line" -lt "$resolve_line" ]] && ok "factory-step.yml keeps the runner before any phase" || bad "factory-step.yml doesn't keep the runner first"
agent_job="$(awk '/^  agent:/{on=1} /^  publish:/{on=0} on' "$wf")"
for ph in agent pack failed; do
  grep -qF "run: bash \"\$RUNNER_TEMP/factory-step.sh\" $ph" <<<"$agent_job" && ! grep -qF ".github/scripts/factory-step.sh $ph" <<<"$agent_job" \
    && ok "agent job runs '$ph' from the kept runner" || bad "agent job runs '$ph' from the checkout"
done
awk '/^  publish:/{on=1} on' "$wf" | grep -q 'RUNNER_TEMP/factory-step.sh' && bad "publish job uses a kept runner" || ok "publish job runs only its own checkout's runner"

fresh; run_a resolve; SCENARIO=ok run_a agent; run_a pack; rm "$SA/report.md"
expect_fail "gate refuses a hand-over without a report" "no bundle or no report" run_p gate
fresh; run_a resolve; SCENARIO=ok run_a agent; run_a pack; echo B9 > "$SA/step"
expect_fail "gate refuses a branch that doesn't match the step" "unexpected step" run_p gate
# A bundle whose history doesn't start from the base (the agent rewrote history).
fresh; run_a resolve; SCENARIO=ok run_a agent
(cd "$A" && g checkout -q --orphan other && g commit -qm orphan --allow-empty && g branch -qf factory/step-b2 other && g checkout -q factory/step-b2 && git bundle create "$SA/agent.bundle" refs/heads/factory/step-b2 >/dev/null 2>&1)
expect_fail "gate refuses history that doesn't start from the base" "does not start from the base" run_p gate

[[ $fails -eq 0 ]] && echo "factory step tests: OK" || echo "factory step tests: FAILED"
exit $fails
