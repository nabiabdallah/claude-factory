#!/usr/bin/env bash
# Tests .github/scripts/new-service.sh (factory ADR 0024) without GitHub, Maven or real tokens: `gh` is a fake that
# records its calls (and what it gets on stdin), new-project.sh is a stand-in, and pushes go to a local bare repo.
#   ci/test-new-service.sh        (from the repo root; needs jq, git)
set -euo pipefail

[[ -x .github/scripts/new-service.sh ]] || { echo "run from the repo root" >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/new-service-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fails=1; }

# A stand-in release: new-project.sh makes a committed, pinned project (or fails, or leaves it unpinned).
rel="$work/release/plugins/java-pipeline/skills/new-project/scripts"; mkdir -p "$rel"
cat > "$rel/new-project.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == --template ]] || exit 9
template="$2" name="$3" pkg="$4" root="$5"
[[ "${FAKE_SCAFFOLD:-ok}" != fail ]] || { echo "verify red" >&2; exit 1; }
mkdir -p "$root/$name/.claude"; cd "$root/$name"
ref='java-pipeline-v0.19.0'; [[ "${FAKE_SCAFFOLD:-ok}" != unpinned ]] || ref=''
printf '{"extraKnownMarketplaces":{"claude-factory":{"source":{"ref":"%s"}}}}\n' "$ref" > .claude/settings.json
echo "$template $pkg" > README.md
git init -q -b main && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -qm "chore: create $name"
echo "new-project: created $root/$name"
SH
chmod +x "$rel/new-project.sh"

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
log="$FAKE_GH/calls"; printf '%s\n' "$*" >> "$log"
case "$*" in
  "api user --jq .login") [[ -f "$FAKE_GH/bad-token" ]] && { echo "gh: Bad credentials (HTTP 401)" >&2; exit 1; }
                          cat "$FAKE_GH/login" 2>/dev/null || echo acme ;;
  "api repos/acme/"*" --jq .full_name") if [[ -f "$FAKE_GH/exists" ]]; then echo acme/x
    elif [[ -f "$FAKE_GH/api-down" ]]; then echo "gh: Server Error (HTTP 500)" >&2; exit 1
    else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
  "api repos/acme/"*" --jq .id") echo 777 ;;
  "api repos/acme/demo/contents/.github/workflows/factory-feature.yml --jq .name") [[ ! -f "$FAKE_GH/not-a-service" ]] || exit 1; echo factory-feature.yml ;;
  "api --paginate installation/repositories --jq .repositories[].full_name") echo "token=$GH_TOKEN" >> "$log"; echo acme/factory; [[ ! -f "$FAKE_GH/app-installed" ]] || echo acme/demo ;;
  "api --method POST user/repos "*) [[ -f "$FAKE_GH/create-fails" ]] && exit 1; echo acme/x ;;
  "secret set "*) printf 'STDIN[%s]\n' "$(cat)" >> "$log" ;;
  "label create "*) ;;
  "api --method PUT user/installations/"*) [[ -f "$FAKE_GH/app-refuses" ]] && { echo "gh: Resource not accessible by personal access token (HTTP 403)" >&2; exit 1; }; true ;;
  # protect-repo.sh: reads visibility and rulesets, then writes
  "api repos/acme/demo") echo '{"visibility":"public"}' ;;
  "api repos/acme/demo/rulesets?includes_parents=false") echo '[]' ;;
  "api --method "*) [[ " $* " != *" --input - "* ]] || cat >/dev/null; echo '{}' ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" FAKE_GH="$work/gh" GH_TOKEN=admin-token OWNER=acme NAME=demo PACKAGE=com.example.demo \
  TEMPLATE=skeleton RELEASE_DIR="$work/release"
unset GITHUB_STEP_SUMMARY 2>/dev/null || true

n=0
fresh() { n=$((n + 1)); rm -rf "$FAKE_GH"; mkdir -p "$FAKE_GH"; : > "$FAKE_GH/calls"; export FACTORY_STATE="$work/s$n"
  rm -rf "$work/remote$n.git"; git init -q --bare "$work/remote$n.git"; export FACTORY_PUSH_URL="$work/remote$n.git"; }
run() { .github/scripts/new-service.sh "$@" > "$work/out" 2>&1; }
expect_ok() { if "${@:2}"; then ok "$1"; else bad "$1: $(tail -n 3 "$work/out")"; fi; }
expect_fail() { if "${@:3}"; then bad "$1 (it passed)"; elif grep -qF -- "$2" "$work/out"; then ok "$1"
  else bad "$1: wrong reason: $(tail -n 3 "$work/out")"; fi; }

# --- check
fresh; expect_ok "check passes good inputs" run check
for bad_name in Demo "demo_service" "-demo" "demo-" "a\$(id)" "$(printf 'x%.0s' {1..41})"; do
  fresh; NAME="$bad_name" expect_fail "check refuses name '${bad_name:0:12}'" "kebab-case" run check
done
fresh; NAME=claude-factory expect_fail "check refuses claude-factory" "reserved" run check
fresh; NAME=payments-service expect_fail "check refuses payments-service" "reserved" run check
fresh; PACKAGE=example expect_fail "check refuses a one-part package" "package must" run check
fresh; PACKAGE='com.Example.x' expect_fail "check refuses an uppercase package" "package must" run check
fresh; TEMPLATE=other expect_fail "check refuses an unknown template" "template must" run check
fresh; touch "$FAKE_GH/exists"; expect_fail "check refuses an existing repo" "already exists" run check
fresh; touch "$FAKE_GH/bad-token"; expect_fail "check stops on a token GitHub rejects" "admin token doesn't work" run check
fresh; echo someone-else > "$FAKE_GH/login"; expect_fail "check stops on another account's token" "belongs to 'someone-else'" run check
fresh; touch "$FAKE_GH/api-down"; expect_fail "check stops when existence can't be checked" "could not check whether" run check

# --- scaffold
fresh; expect_ok "scaffold makes a committed, pinned project" run scaffold
fresh; FAKE_SCAFFOLD=fail expect_fail "scaffold stops when new-project.sh fails" "new-project.sh failed" run scaffold
fresh; FAKE_SCAFFOLD=unpinned expect_fail "scaffold refuses an unpinned project" "not pinned" run scaffold
fresh; RELEASE_DIR="$work/nowhere" expect_fail "scaffold needs the release" "no new-project.sh" run scaffold

# --- create
fresh; expect_fail "create needs a scaffold first" "nothing scaffolded" run create
fresh; run scaffold; expect_ok "create makes the repo and pushes main" run create
grep -qx 'api --method POST user/repos -f name=demo -F private=false -f description=Service built by claude-factory (java-pipeline) --jq .full_name' "$FAKE_GH/calls" \
  && ok "the repo is created public" || bad "create call: $(grep user/repos "$FAKE_GH/calls")"
git --git-dir="$FACTORY_PUSH_URL" rev-parse -q --verify refs/heads/main >/dev/null && ok "main pushed" || bad "main not pushed"
fresh; run scaffold; touch "$FAKE_GH/create-fails"; expect_fail "create stops when GitHub refuses" "could not create" run create

# --- configure
cfg() { PACKAGES_TOKEN=pkg-SECRET CLAUDE_TOKEN=claude-SECRET APP_INSTALLATION_ID=55 APP_KEY=key-SECRET APP_CLIENT_ID=Iv23client run configure; }
fresh; expect_ok "configure sets everything" cfg
c="$FAKE_GH/calls"
[[ $(grep -c '^secret set FACTORY_PACKAGES_TOKEN --repo acme/demo$' "$c") == 1 && $(grep -c '^secret set FACTORY_PACKAGES_TOKEN --app dependabot --repo acme/demo$' "$c") == 1 \
  && $(grep -c '^secret set CLAUDE_CODE_OAUTH_TOKEN --repo acme/demo$' "$c") == 1 ]] && ok "three secrets set" || bad "secrets: $(grep 'secret set' "$c")"
[[ $(grep -c '^STDIN\[pkg-SECRET\]$' "$c") == 2 && $(grep -c '^STDIN\[claude-SECRET\]$' "$c") == 1 ]] && ok "secret values go on stdin" || bad "secret stdin"
! grep -qE 'pkg-SECRET|claude-SECRET|key-SECRET' "$work/out" && ok "no secret value is printed" || bad "a secret value was printed"
! grep -E 'pkg-SECRET|claude-SECRET|key-SECRET' "$c" | grep -qv '^STDIN' && ok "no secret value on a command line" || bad "secret on a command line"
[[ $(grep -c '^secret set FACTORY_APP_KEY --repo acme/demo$' "$c") == 1 && $(grep -c '^STDIN\[key-SECRET\]$' "$c") == 1 \
  && $(grep -c '^secret set FACTORY_APP_CLIENT_ID --repo acme/demo$' "$c") == 1 && $(grep -c '^STDIN\[Iv23client\]$' "$c") == 1 ]] \
  && ok "the service gets the App's key and client id, on stdin (ADR 0028)" || bad "App key: $(grep 'FACTORY_APP' "$c")"
[[ "$(grep -n 'user/installations/55' "$c" | cut -d: -f1)" -lt "$(grep -n 'secret set FACTORY_APP_KEY' "$c" | cut -d: -f1)" ]] \
  && ok "the key is set only after the repo joined the installation" || bad "the key was set before the installation"
for l in factory:spec factory:build risk:high; do grep -q "^label create $l --repo acme/demo " "$c" && ok "label $l" || bad "no label $l"; done
grep -qx 'api --method PUT user/installations/55/repositories/777' "$c" && ok "the App gets the repo" || bad "no App install call"
grep -q 'repos/acme/demo/rulesets' "$c" && ok "protect-repo.sh ran" || bad "protect-repo.sh did not run"
fresh; touch "$FAKE_GH/app-refuses"; expect_ok "configure finishes when the App can't be added" cfg
grep -q 'repos/acme/demo/rulesets' "$FAKE_GH/calls" && ok "guardrails applied even though the App was refused" || bad "no guardrails when the App was refused"
grep -q '::warning::could not add acme/demo' "$work/out" && grep -qF 'settings/installations/55' "$work/out" && grep -qF 'Service app' "$work/out" && ok "a refused App is a warning with the fix" || bad "no warning for the refused App"
! grep -q 'secret set FACTORY_APP' "$FAKE_GH/calls" && ok "a service the App is not on gets no App key (its publish job would fail)" || bad "the key was set without the installation"
fresh; PACKAGES_TOKEN=x CLAUDE_TOKEN=y APP_INSTALLATION_ID=5 APP_CLIENT_ID=c APP_KEY= expect_fail "configure needs the App's key" "APP_KEY is not set" run configure
fresh; PACKAGES_TOKEN=x CLAUDE_TOKEN=y APP_KEY=k APP_CLIENT_ID=c APP_INSTALLATION_ID='5;x' expect_fail "configure refuses a malformed installation id" "not a number" run configure
fresh; PACKAGES_TOKEN= CLAUDE_TOKEN=y APP_KEY=k APP_CLIENT_ID=c APP_INSTALLATION_ID=5 expect_fail "configure needs the packages token" "PACKAGES_TOKEN is not set" run configure

# --- app (an existing service gets the App, ADR 0028)
giveapp() { APP_INSTALLATION_ID=55 APP_KEY=key-SECRET APP_CLIENT_ID=Iv23client APP_TOKEN=app-token run app; }
appkey() { grep -q '^secret set FACTORY_APP_KEY --repo acme/demo$' "$FAKE_GH/calls"; }
fresh; touch "$FAKE_GH/exists"; expect_ok "app: an existing service joins the installation and gets the key" giveapp
appkey && grep -qx 'api --method PUT user/installations/55/repositories/777' "$FAKE_GH/calls" && ok "app: installation, then the key" || bad "app: $(cat "$FAKE_GH/calls")"
! grep -q 'key-SECRET' "$work/out" && ! grep 'key-SECRET' "$FAKE_GH/calls" | grep -qv '^STDIN' && ok "app: the key is neither printed nor on a command line" || bad "app: the key leaked"
! grep -qE 'rulesets|label create|FACTORY_PACKAGES_TOKEN|CLAUDE_CODE' "$FAKE_GH/calls" && ok "app: touches nothing else in the service" || bad "app: did more than the App"
fresh; touch "$FAKE_GH/exists" "$FAKE_GH/app-refuses" "$FAKE_GH/app-installed"; expect_ok "app: the owner added the repo by hand, the admin token is refused: still gets the key" giveapp
appkey && grep -qx 'token=app-token' "$FAKE_GH/calls" && ok "app: membership is read with the App's token" || bad "app: no key for a repo added by hand"
fresh; touch "$FAKE_GH/exists" "$FAKE_GH/app-refuses"; expect_fail "app: not in the installation and can't be added" "did not get the key" giveapp
! appkey && grep -qF 'settings/installations/55' "$work/out" && ok "app: no key without the installation, and the link to add it" || bad "app: key set without the installation"
fresh; expect_fail "app: refuses a repo that doesn't exist" "does not exist" giveapp
fresh; touch "$FAKE_GH/exists" "$FAKE_GH/not-a-service"; expect_fail "app: refuses a repo that isn't a factory service" "not a service" giveapp
for r in claude-factory payments-service; do fresh; touch "$FAKE_GH/exists"; NAME="$r" expect_fail "app: refuses $r" "reserved" giveapp; ! appkey && ok "app: $r gets no key" || bad "app: $r got the key"; done
fresh; touch "$FAKE_GH/exists"; echo mallory > "$FAKE_GH/login"; expect_fail "app: refuses another account's token" "belongs to" giveapp

# --- workflows: the App's key goes to the token action and, as APP_KEY, to the provisioning script only
for wf in .github/workflows/new-service.yml .github/workflows/service-app.yml; do
  odd="$(grep -n 'secrets[.]FACTORY_APP_KEY' "$wf" | grep -vE 'private-key: [$][{][{] secrets[.]FACTORY_APP_KEY [}][}]$|^[0-9]+:          APP_KEY: [$][{][{] secrets[.]FACTORY_APP_KEY [}][}]$' || true)"
  [[ -z "$odd" ]] && ok "$wf: the key only as private-key and APP_KEY" || bad "$wf: FACTORY_APP_KEY used elsewhere: $odd"
  [[ "$(grep -c 'APP_KEY: [$][{][{]' "$wf")" == 1 ]] && sed -n '/APP_KEY: [$][{][{]/,$p' "$wf" | grep -q . \
    && grep -B12 'APP_KEY: [$][{][{]' "$wf" | grep -qE 'run: \.github/scripts/new-service\.sh (configure|app)$' \
    && ok "$wf: APP_KEY goes to one new-service.sh step" || bad "$wf: APP_KEY reaches another step"
  grep -q '^    environment: provisioning$' "$wf" && grep -q 'refs/heads/main' "$wf" && ok "$wf: provisioning environment, main only" || bad "$wf: not tied to main"
  ! grep -qE '^\s+run:.*[$][{][{]' "$wf" && ok "$wf: no run command interpolates an expression" || bad "$wf: a run command interpolates an expression"
done

[[ $fails -eq 0 ]] && echo "new-service tests: OK" || echo "new-service tests: FAILED"
exit $fails
