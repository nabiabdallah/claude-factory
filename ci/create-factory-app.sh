#!/usr/bin/env bash
# Creates the factory's GitHub App from ci/factory-app/manifest.json (factory ADR 0021). The owner runs it twice,
# from the repo root, with an admin `gh` login:
#   ci/create-factory-app.sh form <owner/repo>          writes an HTML page; open it, check the App, click Create
#   ci/create-factory-app.sh convert <code> <owner/repo> exchanges the ?code=… GitHub redirected to for the App's
#                                                        credentials and stores them in <owner/repo>:
#     secret   FACTORY_APP_KEY        the private key (never printed or written to disk)
#     variable FACTORY_APP_CLIENT_ID  the client id (create-github-app-token's `client-id`)
#     variable FACTORY_APP_SLUG       the App's slug (its bot is <slug>[bot])
# Then install the App on the repositories it should act in (the URL is printed).
set -euo pipefail

usage() { echo "usage: $0 form <owner/repo> | $0 convert <code> <owner/repo>" >&2; exit 2; }
repo_ok() { [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; }
command -v jq >/dev/null || { echo "needs jq" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
manifest="$here/factory-app/manifest.json"

case "${1:-}" in
  form)
    [[ $# -eq 2 ]] && repo_ok "$2" || usage
    owner="${2%%/*}"
    state="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    out="$(mktemp "${TMPDIR:-/tmp}/factory-app-form.XXXXXX")"; mv "$out" "$out.html"; out="$out.html"
    # A personal account's Apps are created under /settings/apps/new; an organisation's under its own settings.
    if [[ "$(gh api "users/$owner" -q .type)" == Organization ]]; then
      action="https://github.com/organizations/$owner/settings/apps/new?state=$state"
    else
      action="https://github.com/settings/apps/new?state=$state"
    fi
    value="$(jq -c . "$manifest" | jq -Rr @html)"
    cat > "$out" <<HTML
<!doctype html>
<meta charset="utf-8">
<title>Create the factory's GitHub App</title>
<p>Submitting the App manifest to GitHub. After you click <b>Create GitHub App</b> there, GitHub redirects to a
URL ending in <code>?code=…&amp;state=$state</code>. Check that the state matches, then run
<code>ci/create-factory-app.sh convert &lt;code&gt; $2</code> within an hour.</p>
<form id="f" action="$action" method="post">
  <input type="hidden" name="manifest" value="$value">
  <button type="submit">Continue to GitHub</button>
</form>
HTML
    echo "Open this page in a browser where you're signed in to GitHub as $owner:"
    echo "  $out"
    echo "Expected state in the redirect: $state"
    ;;
  convert)
    [[ $# -eq 3 ]] && repo_ok "$3" || usage
    code="$2" repo="$3"
    [[ "$code" =~ ^[A-Za-z0-9]{8,64}$ ]] || { echo "that doesn't look like a manifest code" >&2; exit 2; }
    # The response holds the private key: keep it in memory, hand the key to gh on stdin, print only public fields.
    app="$(gh api --method POST "app-manifests/$code/conversions")"
    slug="$(jq -r '.slug // empty' <<<"$app")"
    client_id="$(jq -r '.client_id // empty' <<<"$app")"
    [[ -n "$slug" && -n "$client_id" ]] && jq -e '.pem | startswith("-----BEGIN")' <<<"$app" >/dev/null \
      || { echo "unexpected response from GitHub (no slug, client_id or key)" >&2; exit 1; }
    jq -r .pem <<<"$app" | gh secret set FACTORY_APP_KEY --repo "$repo" >/dev/null
    app=""
    gh variable set FACTORY_APP_CLIENT_ID --repo "$repo" --body "$client_id" >/dev/null
    gh variable set FACTORY_APP_SLUG --repo "$repo" --body "$slug" >/dev/null
    echo "created App '$slug'; stored FACTORY_APP_KEY, FACTORY_APP_CLIENT_ID and FACTORY_APP_SLUG in $repo"
    echo "Install it on the repositories it should act in: https://github.com/apps/$slug/installations/new"
    ;;
  *) usage ;;
esac
