#!/usr/bin/env bash
# Stop hook: Claude may not finish while the build is red.
# Runs `mvn verify` (tests + ArchUnit + formatting check) when Java/POM files changed.
# Exit 2 = block stopping; stderr is fed back to Claude so it fixes the failure.
# Gives up after MAX_ATTEMPTS consecutive failures so a stuck agent can't loop forever.
set -uo pipefail

MAX_ATTEMPTS=3
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[[ -f pom.xml ]] || exit 0   # plugin hooks fire in every project; only act on Maven projects
state_file=".claude/.verify-gate-attempts"

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false')"

# Only gate when code changed (tracked or untracked) — chat-only turns stop freely.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  changed="$(git status --porcelain -- '*.java' 'pom.xml' '**/pom.xml' 2>/dev/null)"
  [[ -n "$changed" ]] || { rm -f "$state_file"; exit 0; }
fi

attempts=0
[[ "$active" == "true" && -f "$state_file" ]] && attempts="$(cat "$state_file")"

# Find Java if the session was started without it (e.g. SDKMAN installed later).
if [[ -z "${JAVA_HOME:-}" ]] && ! command -v java >/dev/null 2>&1 && [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  set +u; source "$HOME/.sdkman/bin/sdkman-init.sh"; set -u
fi
mvn_cmd="mvn"; [[ -x ./mvnw ]] && mvn_cmd="./mvnw"
[[ -x "${CLAUDE_PLUGIN_ROOT:-}/bin/mvnw-sandboxed" ]] && mvn_cmd="${CLAUDE_PLUGIN_ROOT}/bin/mvnw-sandboxed"

if out="$($mvn_cmd -q verify 2>&1)"; then
  rm -f "$state_file"
  exit 0
fi

attempts=$((attempts + 1))
mkdir -p .claude && echo "$attempts" > "$state_file"

if (( attempts >= MAX_ATTEMPTS )); then
  rm -f "$state_file"
  {
    echo "verify-gate: build still failing after $MAX_ATTEMPTS attempts. Stopping."
    echo "Tell the user clearly that the work is NOT done and summarise the failure."
  } >&2
  exit 0
fi

{
  echo "verify-gate: 'mvn verify' failed (attempt $attempts/$MAX_ATTEMPTS). The task is not done."
  echo "Fix the cause — do not weaken tests or architecture rules. Last output:"
  printf '%s\n' "$out" | grep -E 'ERROR|FAIL|Tests run:.*Fail|violated|Architecture Violation|expected|but was' | head -n 40
  echo "--- tail ---"
  printf '%s\n' "$out" | tail -n 25
} >&2
exit 2
