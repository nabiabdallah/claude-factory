#!/usr/bin/env bash
# Sets the git author for a factory workflow (factory ADR 0021): the factory's App bot when the workflow minted an
# App token (APP_SLUG set), else github-actions[bot]. Needs GH_TOKEN for the lookup of the bot's user id.
#   APP_SLUG=<slug or empty> .github/scripts/bot-identity.sh
set -euo pipefail

if [[ -n "${APP_SLUG:-}" ]]; then
  [[ "$APP_SLUG" =~ ^[a-z0-9-]+$ ]] || { echo "::error::unexpected App slug" >&2; exit 1; }
  name="${APP_SLUG}[bot]"
  id="$(gh api "users/${name}" -q .id)"
  [[ "$id" =~ ^[0-9]+$ ]] || { echo "::error::no user id for $name" >&2; exit 1; }
else
  name="github-actions[bot]" id=41898282
fi
git config user.name "$name"
git config user.email "${id}+${name}@users.noreply.github.com"
echo "git author: $name"
