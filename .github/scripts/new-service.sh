#!/usr/bin/env bash
# Service provisioning (factory ADR 0024): one workflow run turns a name into a public, protected service repo that
# the factory can work in. .github/workflows/new-service.yml calls the phases in order:
#   check      the inputs are well-formed; the repo doesn't exist; the name isn't reserved
#   scaffold   new-project.sh from the latest java-pipeline release (verify green, first commit)
#   create     create the public repo and push main (the admin token)
#   configure  Actions and Dependabot secrets, labels, the factory's App, protect-repo.sh
# and, for a service that exists already, .github/workflows/service-app.yml calls:
#   app        add the repo to the App's installation and give it the App's key (ADR 0028)
# The admin token comes only from the `provisioning` environment, which only `main` can use. Secret values arrive
# in the environment and go to `gh` on stdin; nothing here prints them. State lives in $FACTORY_STATE.
# Tested with a fake `gh` and a stand-in new-project.sh by ci/test-new-service.sh.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
state="${FACTORY_STATE:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/new-service}"
mkdir -p "$state"
die() { echo "new-service: $*" >&2; echo "$*" > "$state/failure"; exit 1; }
need() { local v; for v in "$@"; do [[ -n "${!v:-}" ]] || die "$v is not set"; done; }
summary() { echo "$*"; [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "$*" >> "$GITHUB_STEP_SUMMARY"; }

# Repos provisioning never touches: the factory itself and the validation service.
reserved='^(claude-factory|payments-service)$'

# Gives $repo the factory's App (ADR 0028): the repo joins the App's installation, then gets the App's key and client
# id as secrets, so its runner opens pull requests as the App and they start CI. The key is set only once the App
# is known to be on the repo: a key without the installation would fail every publish job. Sets $app (for the
# summary) and returns 1 when the App is not on the repo.
give_app() {
  need APP_INSTALLATION_ID APP_KEY APP_CLIENT_ID
  [[ "$APP_INSTALLATION_ID" =~ ^[0-9]+$ ]] || die "the App installation id is not a number"
  local repo_id by_hand="https://github.com/settings/installations/$APP_INSTALLATION_ID"
  repo_id="$(gh api "repos/$repo" --jq .id)"
  [[ "$repo_id" =~ ^[0-9]+$ ]] || die "could not read the id of $repo"
  # Adding a repo to the App's installation may need a classic token (GitHub's docs disagree). If the admin token
  # is refused, the owner may have added the repo by hand: an App token for the whole installation can tell.
  if ! gh api --method PUT "user/installations/$APP_INSTALLATION_ID/repositories/$repo_id" >/dev/null 2>"$state/app.err"; then
    if [[ -z "${APP_TOKEN:-}" ]] || ! GH_TOKEN="$APP_TOKEN" gh api --paginate installation/repositories \
      --jq '.repositories[].full_name' 2>/dev/null | grep -qxF "$repo"; then
      echo "::warning::could not add $repo to the factory's App ($(tr -d '\n' < "$state/app.err")). Add it by hand at $by_hand, then run the \"Service app\" workflow with its name. Until then its runner's pull requests need a close and reopen to start CI."
      app="NOT the App (add it by hand: $by_hand, then run the Service app workflow)"
      return 1
    fi
  fi
  printf '%s' "$APP_KEY" | gh secret set FACTORY_APP_KEY --repo "$repo" >/dev/null \
    || die "could not set the secret FACTORY_APP_KEY"
  # A secret, not a variable: the admin token has no Variables permission, and the runner reads either.
  printf '%s' "$APP_CLIENT_ID" | gh secret set FACTORY_APP_CLIENT_ID --repo "$repo" >/dev/null \
    || die "could not set the secret FACTORY_APP_CLIENT_ID"
  app="the factory's App and its key"
}

phase="${1:-}"
case "$phase" in
  check)
    need OWNER NAME PACKAGE TEMPLATE GH_TOKEN
    [[ "$OWNER" =~ ^[A-Za-z0-9-]+$ ]] || die "owner '$OWNER' is malformed"
    [[ "$NAME" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ && ${#NAME} -le 40 ]] || die "name must be kebab-case, at most 40 characters (e.g. customer-service)"
    [[ ! "$NAME" =~ $reserved ]] || die "$NAME is reserved: provisioning never touches it"
    [[ "$PACKAGE" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$ ]] || die "package must look like com.example.customers"
    [[ "$TEMPLATE" =~ ^(skeleton|payments-example)$ ]] || die "template must be skeleton or payments-example"
    # The admin token must work and be the owner's: a bad token must not read as "the repo doesn't exist".
    login="$(gh api user --jq .login 2>/dev/null)" \
      || die "the admin token doesn't work (FACTORY_ADMIN_TOKEN in the provisioning environment: expired, revoked or mistyped?)"
    [[ "$login" == "$OWNER" ]] || die "the admin token belongs to '$login', not $OWNER"
    if found="$(gh api "repos/$OWNER/$NAME" --jq .full_name 2>&1)"; then
      die "$OWNER/$NAME already exists: provisioning only creates new repos"
    fi
    grep -q 'HTTP 404' <<<"$found" || die "could not check whether $OWNER/$NAME exists: $found"
    echo "new-service: $OWNER/$NAME ($TEMPLATE, package $PACKAGE)"
    ;;

  scaffold)
    need NAME PACKAGE TEMPLATE RELEASE_DIR
    script="$RELEASE_DIR/plugins/java-pipeline/skills/new-project/scripts/new-project.sh"
    [[ -x "$script" ]] || die "no new-project.sh in the release at $RELEASE_DIR"
    rm -rf "$state/projects"
    "$script" --template "$TEMPLATE" "$NAME" "$PACKAGE" "$state/projects" > "$state/scaffold.log" 2>&1 \
      || { tail -n 40 "$state/scaffold.log" >&2; die "new-project.sh failed (see the log above)"; }
    dir="$state/projects/$NAME"
    [[ -d "$dir/.git" && -z "$(git -C "$dir" status --porcelain)" ]] || die "new-project.sh left no clean, committed project"
    jq -e '.extraKnownMarketplaces["claude-factory"].source.ref | test("^java-pipeline-v[0-9]+\\.[0-9]+\\.[0-9]+$")' \
      "$dir/.claude/settings.json" >/dev/null || die "the new project is not pinned to a plugin release"
    tail -n 1 "$state/scaffold.log"
    ;;

  create)
    need OWNER NAME GH_TOKEN
    dir="$state/projects/$NAME"
    [[ -d "$dir/.git" ]] || die "nothing scaffolded (run the scaffold phase)"
    gh api --method POST user/repos -f name="$NAME" -F private=false \
      -f description="Service built by claude-factory (java-pipeline)" --jq .full_name >/dev/null \
      || die "could not create $OWNER/$NAME"
    git -C "$dir" push --quiet "${FACTORY_PUSH_URL:-https://x-access-token:$GH_TOKEN@github.com/$OWNER/$NAME.git}" \
      HEAD:refs/heads/main || die "could not push main to $OWNER/$NAME"
    summary "Created https://github.com/$OWNER/$NAME"
    ;;

  configure)
    need OWNER NAME GH_TOKEN PACKAGES_TOKEN CLAUDE_TOKEN APP_INSTALLATION_ID APP_KEY APP_CLIENT_ID
    repo="$OWNER/$NAME"
    [[ "$APP_INSTALLATION_ID" =~ ^[0-9]+$ ]] || die "the App installation id is not a number"
    printf '%s' "$PACKAGES_TOKEN" | gh secret set FACTORY_PACKAGES_TOKEN --repo "$repo" >/dev/null \
      || die "could not set the Actions secret FACTORY_PACKAGES_TOKEN"
    printf '%s' "$PACKAGES_TOKEN" | gh secret set FACTORY_PACKAGES_TOKEN --app dependabot --repo "$repo" >/dev/null \
      || die "could not set the Dependabot secret FACTORY_PACKAGES_TOKEN"
    printf '%s' "$CLAUDE_TOKEN" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$repo" >/dev/null \
      || die "could not set the secret CLAUDE_CODE_OAUTH_TOKEN"
    while IFS='|' read -r label color text; do
      gh label create "$label" --repo "$repo" --color "$color" --description "$text" --force >/dev/null \
        || die "could not create the label $label"
    done <<'LABELS'
factory:spec|1D76DB|Draft a spec from this issue's idea
factory:build|0E8A16|Build this issue's approved spec
risk:high|B60205|Only the owner merges (ADR 0020)
LABELS
    "$here/../../ci/protect-repo.sh" "$repo" service || die "protect-repo.sh failed on $repo"
    give_app || true
    summary "Configured $repo: secrets, labels, guardrails, $app"
    ;;

  app)
    need OWNER NAME GH_TOKEN
    [[ "$OWNER" =~ ^[A-Za-z0-9-]+$ ]] || die "owner '$OWNER' is malformed"
    [[ "$NAME" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ && ${#NAME} -le 40 ]] || die "name must be kebab-case, at most 40 characters"
    [[ ! "$NAME" =~ $reserved ]] || die "$NAME is reserved: provisioning never touches it"
    login="$(gh api user --jq .login 2>/dev/null)" \
      || die "the admin token doesn't work (FACTORY_ADMIN_TOKEN in the provisioning environment: expired, revoked or mistyped?)"
    [[ "$login" == "$OWNER" ]] || die "the admin token belongs to '$login', not $OWNER"
    repo="$OWNER/$NAME"
    gh api "repos/$repo" --jq .full_name >/dev/null 2>&1 || die "$repo does not exist (or the admin token can't see it)"
    # Only a service of this factory: its runner is what uses the key.
    gh api "repos/$repo/contents/.github/workflows/factory-feature.yml" --jq .name >/dev/null 2>&1 \
      || die "$repo has no factory-feature.yml: it is not a service of this factory"
    give_app || die "the App is not on $repo yet, so it did not get the key (see the warning above)"
    summary "$repo now has $app: its runner's pull requests start CI (from java-pipeline 0.20.1)"
    ;;

  *) echo "usage: new-service.sh check|scaffold|create|configure|app" >&2; exit 2 ;;
esac
