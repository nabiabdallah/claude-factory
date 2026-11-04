#!/usr/bin/env bash
# Tests a generated project's .github/scripts/check-deploy.sh (factory ADR 0012) on a throwaway copy:
# mutable tags, unpromotable commits, and the migration rollout rule across promotions.
#   ci/test-check-deploy.sh <project-dir>    (the project must have Postgres: src/main/resources/db/migration)
# Needs kubectl (for kustomize). Without kubeconform on PATH, set CHECK_DEPLOY_NO_SCHEMA=1.
set -euo pipefail

[[ $# -eq 1 && -d "$1/deploy/k8s/overlays" ]] || { echo "usage: $0 <project-dir with deploy/k8s/overlays>" >&2; exit 2; }
[[ -d "$1/src/main/resources/db/migration" ]] || { echo "$1 has no db/migration (run add-postgres first)" >&2; exit 2; }

work="$(mktemp -d "${TMPDIR:-/tmp}/check-deploy-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp -r "$1" "$work/p"
cd "$work/p"
rm -rf target .git
git init -q -b main
g() { git -c user.name=test -c user.email=test@example.invalid "$@"; }
commit() { git add -A && g commit -q -m "$1" && git rev-parse HEAD; }
c0="$(commit "project")"

export MAIN_REF=main
check=.github/scripts/check-deploy.sh
staging=deploy/k8s/overlays/staging/kustomization.yaml
migrations=src/main/resources/db/migration
fails=0

expect() { # expect pass|fail <description> [base-commit]
  local want="$1" desc="$2" got out
  shift 2
  if out="$("$check" "$@" 2>&1)"; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc (expected $want, got $got)"
    sed 's/^/    /' <<<"$out"
    fails=1
  fi
}
set_tag() { sed -i "s/^\(    newTag: \).*/\1$1/" "$staging"; }
add_recreate() { printf 'components:\n  - ../../components/recreate\n' >> "$staging"; }
drop_recreate() { sed -i '/^components:$/d; /components\/recreate$/d' "$staging"; }
reset_to() { git reset -q --hard "$1"; git clean -qfd; }

expect pass "fresh project (nothing promoted)"

set_tag main
expect fail "mutable tag :main is rejected"
set_tag latest
expect fail "mutable tag :latest is rejected"
reset_to "$c0"

sed -i '/^images:$/,$d' "$staging"
expect fail "image without a tag is rejected"
reset_to "$c0"

git switch -q -c side
g commit -q --allow-empty -m side
side="$(git rev-parse HEAD)"
git switch -q main
set_tag "$side"
expect fail "commit that is not on main is rejected"
set_tag 0123456789abcdef0123456789abcdef01234567
expect fail "unknown commit is rejected"
reset_to "$c0"

set_tag "$c0"
expect pass "first promotion (from unreleased)" "$c0"
p1="$(commit "promote staging to c0")"

printf -- '-- rollout: recreate — test: the old version reads the dropped column\nalter table if exists t drop column if exists x;\n' \
  > "$migrations/V900__drop_x.sql"
c2="$(commit "breaking migration")"
set_tag "$c2"
expect fail "promotion across a recreate migration without components/recreate" "$c2"
add_recreate
expect pass "promotion across a recreate migration with components/recreate" "$c2"
p2="$(commit "promote staging to c2 with recreate")"

expect pass "unchanged tag: rollout rule not evaluated" "$p2"

echo "docs" >> README.md
c3="$(commit "no migration")"
set_tag "$c3"
expect fail "components/recreate left in on a promotion without a recreate migration" "$p2"
drop_recreate
expect pass "components/recreate removed on the next promotion" "$p2"
p3="$(commit "promote staging to c3")"

set_tag "$c0"
expect fail "rollback across a migration is rejected" "$p3"
reset_to "$p3"

printf -- '-- rollout: compatible — test: additive\ncreate table if not exists y (id int);\n' > "$migrations/V901__add_y.sql"
c4="$(commit "compatible migration")"
set_tag "$c4"
expect pass "promotion across a compatible migration, rolling update" "$p3"
reset_to "$p3"

echo "-- edited" >> "$migrations/V900__drop_x.sql"
c5="$(commit "edit a released migration")"
set_tag "$c5"
expect fail "editing a released migration is rejected" "$p3"

[[ "$fails" -eq 0 ]] && echo "check-deploy: all cases behave as expected" || { echo "check-deploy: test FAILED"; exit 1; }
