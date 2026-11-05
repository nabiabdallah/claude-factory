#!/usr/bin/env bash
# Scaffold a new Spring Boot hexagonal service from a java-pipeline template.
# Usage: new-project.sh [--template <name>] <project-name> <base.package> [projects-dir]
#   --template   : a directory under templates/ (default: skeleton). See --list.
#   project-name : kebab-case, e.g. customer-service
#   base.package : lowercase Java package, e.g. com.example.customers
#   projects-dir : defaults to ~/dev/projects
# Each template declares its own base.package and artifact.id in template.properties.
set -euo pipefail

die() { echo "new-project: $*" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
templates_dir="$(cd "$script_dir/../../../templates" && pwd)" || die "templates directory not found"

prop() { sed -n "s/^$1=//p" "$2" | head -n 1; }

template_name="skeleton"
case "${1:-}" in
  --list)
    for t in "$templates_dir"/*/template.properties; do
      printf '%-18s %s\n' "$(basename "$(dirname "$t")")" "$(prop description "$t")"
    done
    exit 0 ;;
  --template)
    [[ $# -ge 2 ]] || die "--template needs a name (see --list)"
    template_name="$2"; shift 2 ;;
  --template=*)
    template_name="${1#--template=}"; shift ;;
esac

[[ $# -ge 2 ]] || die "usage: new-project.sh [--template <name>] <project-name> <base.package> [projects-dir]"
name="$1"; pkg="$2"; dest_root="${3:-$HOME/dev/projects}"

[[ "$name" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] || die "project name must be kebab-case: '$name'"
[[ "$pkg" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] || die "base package must look like com.example.foo: '$pkg'"
[[ "$template_name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid template name: '$template_name'"

template="$templates_dir/$template_name"
props="$template/template.properties"
[[ -f "$props" ]] || die "unknown template '$template_name' (see --list)"
old_pkg="$(prop base.package "$props")"
old_artifact="$(prop artifact.id "$props")"
[[ -n "$old_pkg" && -n "$old_artifact" ]] || die "$props must set base.package and artifact.id"

dest="$dest_root/$name"
[[ ! -e "$dest" ]] || die "$dest already exists; refusing to overwrite"

old_path="${old_pkg//.//}"
new_path="${pkg//.//}"
old_group="${old_pkg%.*}"
group_id="${pkg%.*}"

mkdir -p "$dest_root"
cp -r "$template" "$dest"
# Until the build runs, any failure removes the partial copy so a rerun isn't blocked.
cleanup_partial=1
trap '[[ $? -ne 0 && ${cleanup_partial:-0} -eq 1 ]] && rm -rf "$dest" && echo "new-project: removed partial copy $dest" >&2' EXIT
cd "$dest"
rm -f template.properties

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

# Maven groupId: only the project's own (first) occurrence, not the Spring Boot parent's.
old_group_re="${old_group//./\\.}"
sed -i -e "0,/<groupId>${old_group_re}<\/groupId>/s//<groupId>${group_id}<\/groupId>/" pom.xml

# The template's artifact id names the project everywhere (pom artifactId/name, application name, README).
grep -rIl --exclude-dir=.git --exclude-dir=target -F "$old_artifact" . | while IFS= read -r f; do
  sed -i "s/${old_artifact}/${name}/g" "$f"
done

# Leftover check only makes sense when the new package doesn't itself contain the old name
# (same package, or nested like com.example.payments.core, would always match).
if [[ "$pkg" != *"$old_pkg"* ]] && grep -rIq --exclude-dir=.git --exclude-dir=target "$old_re" .; then
  die "leftover references to $old_pkg after rename"
fi

# Pin the plugin marketplace to the release that created this project (factory ADR 0015): the project keeps the
# agents, skills and hooks its tests were written for until someone bumps the ref.
plugin_version="$(sed -n 's/^ *"version": "\(.*\)",$/\1/p' "$script_dir/../../../.claude-plugin/plugin.json" | head -n 1)"
[[ -n "$plugin_version" ]] || die "could not read the plugin version"
python3 -I - .claude/settings.json "java-pipeline-v${plugin_version}" <<'PY'
import json, sys
path, ref = sys.argv[1], sys.argv[2]
settings = json.load(open(path))
source = settings["extraKnownMarketplaces"]["claude-factory"]["source"]
source["ref"] = ref
source["sparsePaths"] = [".claude-plugin", "plugins"]
open(path, "w").write(json.dumps(settings, indent=2) + "\n")
PY

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
git commit -q -m "chore: create ${name} from java-pipeline ${template_name} template"

echo "new-project: created $dest from template '$template_name' (package $pkg), ./mvnw verify green, initial commit $(git rev-parse --short HEAD)"
