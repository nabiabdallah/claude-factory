#!/usr/bin/env bash
# Scaffold a new Spring Boot hexagonal service from the java-pipeline template.
# Usage: new-project.sh <project-name> <base.package> [projects-dir]
#   project-name : kebab-case, e.g. payments-service
#   base.package : lowercase Java package, e.g. com.example.payments
#   projects-dir : defaults to ~/dev/projects
set -euo pipefail

die() { echo "new-project: $*" >&2; exit 1; }

[[ $# -ge 2 ]] || die "usage: new-project.sh <project-name> <base.package> [projects-dir]"
name="$1"; pkg="$2"; dest_root="${3:-$HOME/dev/projects}"

[[ "$name" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] || die "project name must be kebab-case: '$name'"
[[ "$pkg" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] || die "base package must look like com.example.foo: '$pkg'"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$(cd "$script_dir/../../../templates/spring-service" && pwd)" || die "template not found"
dest="$dest_root/$name"
[[ ! -e "$dest" ]] || die "$dest already exists; refusing to overwrite"

old_pkg="com.example.payments"
old_path="${old_pkg//.//}"
new_path="${pkg//.//}"
group_id="${pkg%.*}"

mkdir -p "$dest_root"
cp -r "$template" "$dest"
# Until the build runs, any failure removes the partial copy so a rerun isn't blocked.
cleanup_partial=1
trap '[[ $? -ne 0 && ${cleanup_partial:-0} -eq 1 ]] && rm -rf "$dest" && echo "new-project: removed partial copy $dest" >&2' EXIT
cd "$dest"

# Move source trees to the new package path.
for root in src/main/java src/test/java; do
  [[ -d "$root/$old_path" ]] || continue
  if [[ "$new_path" != "$old_path" ]]; then
    # Move via a temp dir so a new package nested under the old one still works.
    tmp="$dest/.pkg-move"
    mv "$root/$old_path" "$tmp"
    find "$root" -type d -empty -delete 2>/dev/null || true
    mkdir -p "$(dirname "$root/$new_path")"
    mv "$tmp" "$root/$new_path"
  fi
done

# Rewrite package references everywhere (Java sources, ArchitectureTest constants, docs, CLAUDE.md).
# Escape dots so sed matches them literally.
old_re="${old_pkg//./\\.}"
grep -rIl --exclude-dir=.git --exclude-dir=target "$old_re" . | while IFS= read -r f; do
  sed -i "s/${old_re}/${pkg}/g" "$f"
done

# Maven coordinates.
sed -i \
  -e "0,/<groupId>com.example<\/groupId>/s//<groupId>${group_id}<\/groupId>/" \
  -e "s/<artifactId>payments-starter<\/artifactId>/<artifactId>${name}<\/artifactId>/" \
  -e "s/<name>payments-starter<\/name>/<name>${name}<\/name>/" \
  pom.xml

# Leftover check only makes sense when the new package doesn't itself contain the old name
# (same package, or nested like com.example.payments.core, would always match).
if [[ "$pkg" != *"$old_pkg"* ]] && grep -rIq --exclude-dir=.git --exclude-dir=target "$old_re" .; then
  die "leftover references to $old_pkg after rename"
fi

# Find Java if the session was started without it (e.g. SDKMAN installed later).
if [[ -z "${JAVA_HOME:-}" ]] && ! command -v java >/dev/null 2>&1 && [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  set +u; source "$HOME/.sdkman/bin/sdkman-init.sh"; set -u
fi

chmod +x mvnw
cleanup_partial=0   # from here on, keep the directory so a failed build can be inspected
git init -q
# Longer package names change line lengths; re-format once so spotless:check in verify passes.
"$script_dir/../../../bin/mvnw-sandboxed" -q -B spotless:apply || die "spotless:apply failed in $dest"
"$script_dir/../../../bin/mvnw-sandboxed" -q -B verify || die "./mvnw verify failed in $dest — project left in place, not committed"
git add -A
git commit -q -m "chore: create ${name} from java-pipeline spring-service template"

echo "new-project: created $dest (package $pkg), ./mvnw verify green, initial commit $(git rev-parse --short HEAD)"
