#!/usr/bin/env bash
# PostToolUse: format a Java file right after Claude edits it.
# Never blocks: a formatting problem is reported, not fatal.
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

[[ "$file" == *.java ]] || exit 0
[[ -f "$file" ]] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[[ -f pom.xml ]] || exit 0   # plugin hooks fire in every project; only act on Maven projects
# Find Java if the session was started without it (e.g. SDKMAN installed later).
if [[ -z "${JAVA_HOME:-}" ]] && ! command -v java >/dev/null 2>&1 && [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  set +u; source "$HOME/.sdkman/bin/sdkman-init.sh"; set -u
fi
mvn_cmd="mvn"; [[ -x ./mvnw ]] && mvn_cmd="./mvnw"

# Format only the touched file (fast); Spotless matches by regex on the path.
if ! out="$($mvn_cmd -q spotless:apply -DspotlessFiles="$(printf '%s' "$file" | sed 's/[.[\*^$()+?{|]/\\&/g')" 2>&1)"; then
  echo "format-java: spotless failed on $file (non-blocking)" >&2
  printf '%s\n' "$out" | tail -n 15 >&2
fi
exit 0
