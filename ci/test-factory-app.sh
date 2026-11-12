#!/usr/bin/env bash
# Tests the factory App pieces (factory ADR 0021) without GitHub: the manifest asks for exactly the approved
# permissions; create-factory-app.sh's form carries the manifest and a state, and convert stores the key without
# ever printing it; bot-identity.sh sets the right git author; workflows hand the key only to the token action.
#   ci/test-factory-app.sh        (from the repo root; needs jq, python3, git)
set -euo pipefail

[[ -f ci/create-factory-app.sh ]] || { echo "run from the repo root" >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/factory-app-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0
root="$PWD"
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }
expect() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# --- manifest
m=ci/factory-app/manifest.json
expect "manifest permissions are exactly metadata:read, contents/pull_requests/issues/workflows:write" \
  "jq -e '.default_permissions == {metadata:\"read\",contents:\"write\",pull_requests:\"write\",issues:\"write\",workflows:\"write\"}' $m >/dev/null"
expect "manifest: no webhook, no events, private App" \
  "jq -e '.hook_attributes.active == false and .default_events == [] and .public == false' $m >/dev/null"

# --- a fake gh: logs calls (and stdin of secret set), answers the reads the scripts make
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
log="$FAKE_GH_LOG"; printf '%s\n' "$*" >> "$log"
case "$*" in
  "api users/acme -q .type") echo "${FAKE_OWNER_TYPE:-User}" ;;
  "api --method POST app-manifests/"*"/conversions") printf '%s\n' "$FAKE_CONVERSION" ;;
  "secret set FACTORY_APP_KEY --repo acme/factory") { printf 'STDIN<<'; cat; printf '>>\n'; } >> "$log" ;;
  "variable set "*) ;;
  "api users/factory-bot[bot] -q .id") echo 4242 ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$work/bin/gh"
export FAKE_GH_LOG="$work/gh.log" PATH="$work/bin:$PATH" TMPDIR="$work"

# --- form
for type in User Organization; do
  : > "$FAKE_GH_LOG"
  out="$(FAKE_OWNER_TYPE=$type ci/create-factory-app.sh form acme/factory)"
  page="$(sed -n 's/^  \(.*\.html\)$/\1/p' <<<"$out")"
  state="$(sed -n 's/^Expected state in the redirect: //p' <<<"$out")"
  expect "form ($type): writes a page and a 32-hex state" "[[ -f '$page' && '$state' =~ ^[0-9a-f]{32}$ ]]"
  if [[ $type == User ]]; then want="https://github.com/settings/apps/new?state=$state"
  else want="https://github.com/organizations/acme/settings/apps/new?state=$state"; fi
  expect "form ($type): posts to $want" "grep -qF 'action=\"$want\" method=\"post\"' '$page'"
  python3 -I - "$page" "$m" > "$work/same" <<'PY'
import html, json, re, sys
page = open(sys.argv[1]).read()
value = re.search(r'name="manifest" value="([^"]*)"', page).group(1)
print(json.loads(html.unescape(value)) == json.load(open(sys.argv[2])))
PY
  expect "form ($type): the page carries the manifest unchanged" "[[ \$(cat '$work/same') == True ]]"
done

# --- convert
pem=$'-----BEGIN RSA PRIVATE KEY-----\nSECRET-KEY-MATERIAL\n-----END RSA PRIVATE KEY-----'
for code in "" "x" 'abc$(id)def' "has space here"; do
  : > "$FAKE_GH_LOG"
  if ci/create-factory-app.sh convert "$code" acme/factory >/dev/null 2>&1; then bad "convert rejects code '$code'"
  elif [[ -s "$FAKE_GH_LOG" ]]; then bad "convert calls gh for bad code '$code'"; else ok "convert rejects code '$code'"; fi
done

: > "$FAKE_GH_LOG"
export FAKE_CONVERSION="$(jq -n --arg pem "$pem" '{id: 7, slug: "factory-bot", client_id: "Iv23abc", pem: $pem, client_secret: "CLIENT-SECRET", webhook_secret: null}')"
out="$(ci/create-factory-app.sh convert 0123abcdEF4567 acme/factory 2>&1)"
expect "convert: the key goes to the secret on stdin" "grep -qF 'SECRET-KEY-MATERIAL' '$FAKE_GH_LOG' && grep -q '^secret set FACTORY_APP_KEY --repo acme/factory$' '$FAKE_GH_LOG'"
expect "convert: sets the client id and slug variables" \
  "grep -qx 'variable set FACTORY_APP_CLIENT_ID --repo acme/factory --body Iv23abc' '$FAKE_GH_LOG' && grep -qx 'variable set FACTORY_APP_SLUG --repo acme/factory --body factory-bot' '$FAKE_GH_LOG'"
expect "convert: prints neither the key nor the client secret" "! grep -qE 'SECRET-KEY-MATERIAL|CLIENT-SECRET' <<<\"\$out\""
expect "convert: prints the install URL" "grep -qF 'https://github.com/apps/factory-bot/installations/new' <<<\"\$out\""
expect "convert: writes no file with the key" "! grep -rlF 'SECRET-KEY-MATERIAL' '$work' --exclude=gh.log | grep -q ."

: > "$FAKE_GH_LOG"
export FAKE_CONVERSION='{"slug":"factory-bot","client_id":"Iv23abc"}'
if ci/create-factory-app.sh convert 0123abcdEF4567 acme/factory >/dev/null 2>&1; then bad "convert fails on a response without a key"
elif grep -q '^secret set' "$FAKE_GH_LOG"; then bad "convert sets a secret from a bad response"; else ok "convert fails on a response without a key"; fi

# --- bot-identity.sh
repo="$work/repo"; git init -q "$repo"
(cd "$repo" && APP_SLUG=factory-bot "$root/.github/scripts/bot-identity.sh" >/dev/null)
expect "bot-identity: App bot as author" \
  "[[ \$(git -C '$repo' config user.name) == 'factory-bot[bot]' && \$(git -C '$repo' config user.email) == '4242+factory-bot[bot]@users.noreply.github.com' ]]"
(cd "$repo" && APP_SLUG= "$root/.github/scripts/bot-identity.sh" >/dev/null)
expect "bot-identity: github-actions[bot] without an App" \
  "[[ \$(git -C '$repo' config user.email) == '41898282+github-actions[bot]@users.noreply.github.com' ]]"
expect "bot-identity: rejects an odd slug" "! (cd '$repo' && APP_SLUG='x\$(id)' '$root/.github/scripts/bot-identity.sh' >/dev/null 2>&1)"

# --- workflows: the key reaches only the token action; no expression inside a run command
key_ok='private-key: [$][{][{] secrets[.]FACTORY_APP_KEY [}][}]$|HAS_KEY: [$][{][{] secrets[.]FACTORY_APP_KEY != .. [}][}]$'
key_lines() { grep -n 'secrets[.]FACTORY_APP_KEY' "$1" | grep -v '^[0-9]*:\s*#' | grep -vE "$key_ok" || true; }
for wf in .github/workflows/factory-identity.yml .github/workflows/base-image.yml; do
  if [[ -z "$(key_lines "$wf")" ]]; then ok "$wf: FACTORY_APP_KEY only as the token action's private-key"
  else bad "$wf: FACTORY_APP_KEY used elsewhere: $(key_lines "$wf")"; fi
  if grep -qE '^\s+run:.*[$][{][{]' "$wf"; then bad "$wf: a run command interpolates an expression"
  else ok "$wf: no run command interpolates an expression"; fi
done
# The check itself catches a misuse.
printf '        env:\n          K: ${{ secrets.FACTORY_APP_KEY }}\n' > "$work/leak.yml"
if [[ -n "$(key_lines "$work/leak.yml")" ]]; then ok "key check catches the key in an env"; else bad "key check misses the key in an env"; fi

[[ $fails -eq 0 ]] && echo "factory App tests: OK" || echo "factory App tests: FAILED"
exit $fails
