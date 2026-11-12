#!/usr/bin/env bash
# Service provisioning (factory ADR 0024): one workflow run turns a name into a public, protected service repo that
# the factory can work in. .github/workflows/new-service.yml calls the phases in order:
#   check      the inputs are well-formed; the repo doesn't exist; the name isn't reserved
#   scaffold   new-project.sh from the latest java-pipeline release (verify green, first commit)
#   create     create the public repo and push main (the admin token)
#   configure  Actions and Dependabot secrets, labels, the factory's App, protect-repo.sh
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

phase="${1:-}"
case "$phase" in
  check)
    need OWNER NAME PACKAGE TEMPLATE GH_TOKEN
    [[ "$OWNER" =~ ^[A-Za-z0-9-]+$ ]] || die "owner '$OWNER' is malformed"
    [[ "$NAME" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ && ${#NAME} -le 40 ]] || die "name must be kebab-case, at most 40 characters (e.g. customer-service)"
    [[ ! "$NAME" =~ $reserved ]] || die "$NAME is reserved: provisioning never touches it"
    [[ "$PACKAGE" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$ ]] || die "package must look like com.example.customers"
    [[ "$TEMPLATE" =~ ^(skeleton|payments-example)$ ]] || die "template must be skeleton or payments-example"
    if gh api "repos/$OWNER/$NAME" --jq .full_name >/dev/null 2>&1; then
      die "$OWNER/$NAME already exists: provisioning only creates new repos"
    fi
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
    need OWNER NAME GH_TOKEN PACKAGES_TOKEN CLAUDE_TOKEN APP_INSTALLATION_ID
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
    repo_id="$(gh api "repos/$repo" --jq .id)"
    [[ "$repo_id" =~ ^[0-9]+$ ]] || die "could not read the id of $repo"
    gh api --method PUT "user/installations/$APP_INSTALLATION_ID/repositories/$repo_id" >/dev/null \
      || die "could not add $repo to the factory's App"
    "$here/../../ci/protect-repo.sh" "$repo" service || die "protect-repo.sh failed on $repo"
    summary "Configured $repo: secrets, labels, the factory's App, guardrails"
    ;;

  *) echo "usage: new-service.sh check|scaffold|create|configure" >&2; exit 2 ;;
esac
