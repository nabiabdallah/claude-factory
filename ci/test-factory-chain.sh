#!/usr/bin/env bash
# Tests .github/scripts/factory-chain.sh (factory ADR 0026) without GitHub: `gh` is a fake that answers from files
# and records its calls, in a throwaway copy of the files the script reads.
#   ci/test-factory-chain.sh        (from the repo root)
set -euo pipefail

[[ -x .github/scripts/factory-chain.sh ]] || { echo "run from the repo root" >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/factory-chain-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }

# --- a throwaway factory repo: the two scripts, the release check with its versioned files, a queue
r="$work/r"
for f in .github/scripts/factory-chain.sh .github/scripts/factory-step.sh ci/check-release-notes.sh \
  plugins/java-pipeline/.claude-plugin/plugin.json plugins/java-pipeline/CHANGELOG.md \
  parents/factory-parent/pom.xml parents/factory-parent/CHANGELOG.md; do
  mkdir -p "$r/$(dirname "$f")"; cp "$f" "$r/$f"
done
mkdir -p "$r/docs"
queue() { printf '| # | Step | Gap | Done when |\n|---|---|---|---|\n| B3 ✅ | Done | x | x |\n%s\n' "$1" > "$r/docs/ROADMAP.md"; }
plugin_tag="$(ci/check-release-notes.sh --tags | sed -n 1p)"; parent_tag="$(ci/check-release-notes.sh --tags | sed -n 2p)"
[[ "$plugin_tag" == java-pipeline-v* && "$parent_tag" == factory-parent-v* ]] && ok "--tags prints both components' tags" || bad "--tags: $plugin_tag $parent_tag"

mkdir -p "$work/bin" "$work/gh"
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH/calls"
case "$*" in
  "pr list "*) [[ ! -f "$FAKE_GH/pr-list-fails" ]] || exit 1; cat "$FAKE_GH/open-prs" 2>/dev/null || true ;;
  "api repos/acme/factory/branches/"*) [[ -f "$FAKE_GH/branch-exists" ]] && echo branch || exit 1 ;;
  "api repos/acme/factory/actions/workflows/factory-step.yml/runs"*) cat "$FAKE_GH/last-run" 2>/dev/null || true ;;
  "api --method POST repos/acme/factory/actions/workflows/factory-step.yml/dispatches "*) ;;
  "api repos/acme/factory/git/ref/tags/"*)
    tag="${2##*/}"
    [[ ! -f "$FAKE_GH/tags-fail" ]] || { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }
    grep -qx "$tag" "$FAKE_GH/tags" 2>/dev/null && echo "refs/tags/$tag" || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; } ;;
  "api --method POST repos/acme/factory/git/refs "*) ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$work/bin/gh"
sha=1111111111111111111111111111111111111111 other=2222222222222222222222222222222222222222
export PATH="$work/bin:$PATH" FAKE_GH="$work/gh" GITHUB_REPOSITORY=acme/factory GITHUB_SHA="$sha" GH_TOKEN=t
unset GITHUB_STEP_SUMMARY FACTORY_PAUSED 2>/dev/null || true

fresh() { rm -rf "$work/gh"/*; : > "$work/gh/calls"; queue '| B4 | Chaining | x | x |
| B5 | Tiers | x | x |'; }
run() { (cd "$r" && .github/scripts/factory-chain.sh "$@") > "$work/out" 2>&1; }
dispatched() { grep -q 'dispatches' "$FAKE_GH/calls"; }
starts() { # starts <description>: the run passes and dispatches
  if run next-step && dispatched; then ok "$1"; else bad "$1: $(tail -n 2 "$work/out")"; fi
}
holds() { # holds <description> <reason part>: the run passes, dispatches nothing and says why
  if ! run next-step; then bad "$1: failed: $(tail -n 2 "$work/out")"
  elif dispatched; then bad "$1: it dispatched a step"
  elif grep -qF -- "$2" "$work/out"; then ok "$1"
  else bad "$1: wrong reason: $(tail -n 2 "$work/out")"; fi
}

# --- next-step
fresh; starts "starts the first unfinished step when nothing is in the way"
grep -qx 'api --method POST repos/acme/factory/actions/workflows/factory-step.yml/dispatches -f ref=main -f inputs\[step\]=B4' "$FAKE_GH/calls" \
  && ok "dispatches factory-step.yml on main for B4" || bad "dispatch call: $(grep dispatches "$FAKE_GH/calls")"
fresh; FACTORY_PAUSED=true holds "holds while paused" "paused"
[[ ! -s "$FAKE_GH/calls" ]] && ok "(and asks GitHub nothing)" || bad "paused but called gh: $(cat "$FAKE_GH/calls")"
fresh; queue '| B4 (built, awaiting the owner) | Chaining | x | x |'; holds "holds when the queue has no runnable step" "no unfinished step"
fresh; echo factory/step-b3 > "$FAKE_GH/open-prs"; holds "holds while a step PR is open" "one step at a time"
fresh; echo feat/something > "$FAKE_GH/open-prs"; starts "another open PR doesn't hold the queue"
fresh; touch "$FAKE_GH/branch-exists"; holds "holds while the step's branch exists" "already exists"
fresh; echo "in_progress none $other" > "$FAKE_GH/last-run"; holds "holds while a step run is running" "queued or running"
fresh; echo "queued none $other" > "$FAKE_GH/last-run"; holds "holds while a step run is queued" "queued or running"
fresh; echo "completed failure $sha" > "$FAKE_GH/last-run"; holds "holds after a failed run on the same commit" "nothing has merged since"
fresh; echo "completed cancelled $sha" > "$FAKE_GH/last-run"; holds "holds after a cancelled run on the same commit" "nothing has merged since"
fresh; echo "completed failure $other" > "$FAKE_GH/last-run"; starts "starts again once something merged after a failed run"
fresh; echo "completed success $sha" > "$FAKE_GH/last-run"; starts "starts after a successful run"
fresh; touch "$FAKE_GH/pr-list-fails"
if run next-step; then bad "a failed GitHub call must fail the run"; elif dispatched; then bad "dispatched after a failed GitHub call"
else ok "a failed GitHub call fails the run and starts nothing"; fi

# --- release
tagged() { grep -q "git/refs -f ref=refs/tags/$1 -f sha=$sha" "$FAKE_GH/calls"; }
fresh; printf '%s\n%s\n' "$plugin_tag" "$parent_tag" > "$FAKE_GH/tags"
if run release && ! grep -q 'git/refs ' "$FAKE_GH/calls"; then ok "release: nothing to tag when both tags exist"; else bad "release, tags exist: $(tail -n 2 "$work/out")"; fi
fresh; echo "$parent_tag" > "$FAKE_GH/tags"
if run release && tagged "$plugin_tag" && ! tagged "$parent_tag"; then ok "release: tags the plugin's new version on the merged commit, and only that"
else bad "release, plugin: $(tail -n 2 "$work/out")"; fi
fresh; echo "$plugin_tag" > "$FAKE_GH/tags"
if run release && tagged "$parent_tag"; then ok "release: tags factory-parent's new version"; else bad "release, parent: $(tail -n 2 "$work/out")"; fi
fresh; touch "$FAKE_GH/tags-fail"
if run release; then bad "release: a failed lookup must not read as 'no tag'"; elif grep -q 'git/refs ' "$FAKE_GH/calls"; then bad "release: tagged after a failed lookup"
else ok "release: a failed tag lookup fails the run and tags nothing"; fi
# A version bump without its changelog section is not released.
fresh; cp "$r/plugins/java-pipeline/.claude-plugin/plugin.json" "$work/plugin.json"
sed -i 's/^\( *"version": "\).*",$/\199.0.0",/' "$r/plugins/java-pipeline/.claude-plugin/plugin.json"
echo "$parent_tag" > "$FAKE_GH/tags"
if run release; then bad "release: tagged a version without a changelog section"; elif grep -q 'git/refs ' "$FAKE_GH/calls"; then bad "release: created a tag without notes"
else ok "release: a version without a changelog section is not tagged"; fi
sed -i 's/^\( *"version": "\).*",$/\11.0.0-SNAPSHOT",/' "$r/plugins/java-pipeline/.claude-plugin/plugin.json"
if run release && ! grep -q 'git/refs ' "$FAKE_GH/calls" && grep -q 'not a release version' "$work/out"; then ok "release: a -SNAPSHOT version is not tagged"
else bad "release, snapshot: $(tail -n 2 "$work/out")"; fi
cp "$work/plugin.json" "$r/plugins/java-pipeline/.claude-plugin/plugin.json"
fresh; GITHUB_SHA=main
if run release; then bad "release: accepted a ref that is not a commit id"; else ok "release: refuses a ref that is not a commit id"; fi
GITHUB_SHA="$sha"

# --- workflows: the chain only dispatches; the tag is created with the App's token
grep -q 'factory-chain.sh next-step' .github/workflows/factory-chain.yml && ! grep -qE 'contents: write|FACTORY_APP_KEY' .github/workflows/factory-chain.yml \
  && ok "factory-chain.yml holds no write access to contents and no App key" || bad "factory-chain.yml asks for more than a dispatch"
grep -q 'GH_TOKEN: [$][{][{] steps.app.outputs.token [}][}]' .github/workflows/release-tag.yml \
  && ok "release-tag.yml tags with the App's token (so the release workflows start)" || bad "release-tag.yml doesn't use the App's token"

[[ $fails -eq 0 ]] && echo "factory chain tests: OK" || echo "factory chain tests: FAILED"
exit $fails
