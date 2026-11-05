#!/usr/bin/env bash
# Tests factory-parent's build rules (factory ADR 0013) on throwaway copies of a generated project: each case
# breaks one rule and expects the build to fail with that rule's message.
#   ci/test-build-hygiene.sh <project-dir>     (a project created by new-project; it must already build)
# MVN overrides the Maven command (default: the project's ./mvnw).
set -euo pipefail

[[ $# -eq 1 && -f "$1/pom.xml" ]] || { echo "usage: $0 <project-dir>" >&2; exit 2; }
src="$(cd "$1" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/build-hygiene-test.XXXXXX")"
# Fake artifacts go to the local repo under test.factory; removed again on exit.
trap 'rm -rf "$work" "${HOME}/.m2/repository/test/factory"' EXIT
mvn=(${MVN:-./mvnw} -B -ntp)
fails=0

fresh() { # fresh <case>: a clean copy of the project, cwd inside it
  rm -rf "$work/case"
  cp -r "$src" "$work/case"
  rm -rf "$work/case/target"
  cd "$work/case"
}
add_dep() { # add_dep <xml>: first dependency of the project
  python3 -I - pom.xml "$1" <<'PY'
import sys
path, dep = sys.argv[1], sys.argv[2]
pom = open(path).read()
anchor = "  <dependencies>\n"
assert anchor in pom
open(path, "w").write(pom.replace(anchor, anchor + dep + "\n", 1))
PY
}
add_property() { # add_property <xml>
  python3 -I - pom.xml "$1" <<'PY'
import sys
path, prop = sys.argv[1], sys.argv[2]
pom = open(path).read()
anchor = "  <properties>\n"
if anchor in pom:
    pom = pom.replace(anchor, anchor + prop + "\n", 1)
else:  # generated projects take all properties from factory-parent
    deps = "  <dependencies>\n"
    assert deps in pom, "project has neither <properties> nor <dependencies>"
    pom = pom.replace(deps, anchor + prop + "\n  </properties>\n\n" + deps, 1)
open(path, "w").write(pom)
PY
}
install_fake() { # install_fake <groupId> <artifactId> <version> <file>: into the local repo, no network
  "${mvn[@]}" -q install:install-file -Dfile="$4" -DgroupId="$1" -DartifactId="$2" -Dversion="$3" \
    -Dpackaging=jar -DgeneratePom=true
}
expect_fail() { # expect_fail <description> <expected output regex> <maven goal>
  local desc="$1" want="$2" goal="$3" out
  if out="$("${mvn[@]}" "$goal" 2>&1)"; then
    echo "FAIL - $desc (build passed)"
    fails=1
  elif grep -Eq "$want" <<<"$out"; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc (build failed, but not with /$want/)"
    grep -E '\[(ERROR|WARNING)\]' <<<"$out" | head -n 20 | sed 's/^/    /'
    fails=1
  fi
  cd "$src"
}

# A jar whose only class claims Java 22 (class-file major version 66): only the header matters to the rule.
mkdir -p "$work/fake/p"
printf '\xca\xfe\xba\xbe\x00\x00\x00\x42' > "$work/fake/p/Future.class"
(cd "$work/fake" && python3 -I -c 'import zipfile; z=zipfile.ZipFile("java22.jar","w"); z.write("p/Future.class"); z.close()')
(cd "$work/fake" && python3 -I -c 'import zipfile; zipfile.ZipFile("empty.jar","w").close()')

fresh
add_dep '    <dependency><groupId>junit</groupId><artifactId>junit</artifactId><version>4.13.2</version><scope>test</scope></dependency>'
expect_fail "banned dependency (JUnit 4)" 'junit:junit:jar:4\.13\.2' validate

fresh
install_fake test.factory snapshot-lib 1.0-SNAPSHOT "$work/fake/empty.jar"
add_dep '    <dependency><groupId>test.factory</groupId><artifactId>snapshot-lib</artifactId><version>1.0-SNAPSHOT</version></dependency>'
expect_fail "SNAPSHOT dependency" 'RequireReleaseDeps|snapshot-lib' validate

fresh
install_fake test.factory java22-lib 1.0 "$work/fake/java22.jar"
add_dep '    <dependency><groupId>test.factory</groupId><artifactId>java22-lib</artifactId><version>1.0</version></dependency>'
expect_fail "dependency compiled for a newer Java than 21" 'EnforceBytecodeVersion|java22-lib' validate

fresh
python3 -I - pom.xml <<'PY'
import sys
path = sys.argv[1]
pom = open(path).read()
anchor = "    <plugins>\n"
assert anchor in pom, "project has no <build><plugins>"
plugin = "      <plugin><groupId>org.codehaus.mojo</groupId><artifactId>exec-maven-plugin</artifactId></plugin>\n"
open(path, "w").write(pom.replace(anchor, anchor + plugin, 1))
PY
expect_fail "plugin without a version" 'RequirePluginVersions|exec-maven-plugin' validate

fresh
add_property '    <factory.coverage.line.minimum>0.50</factory.coverage.line.minimum>'
expect_fail "coverage floor lowered in the project POM" 'factory\.coverage\.line\.minimum' validate

fresh
add_property '    <factory.coverage.branch.minimum>0.10</factory.coverage.branch.minimum>'
expect_fail "branch floor lowered in the project POM" 'factory\.coverage\.branch\.minimum' validate

fresh
app="$(grep -rl --include='*.java' '@SpringBootApplication' src/main/java | head -n 1)"
pkg_dir="$(dirname "$app")"
pkg="$(sed -n 's/^package \([a-z0-9_.]*\);.*/\1/p' "$app")"
{
  echo "package ${pkg}.domain;"
  echo
  echo "/** Deliberately untested (build-hygiene test). */"
  echo "public final class Untested {"
  echo "    private Untested() {}"
  for i in $(seq 1 60); do
    echo "    public static int f$i(int x) {"
    echo "        if (x > $i) {"
    echo "            return x - $i;"
    echo "        }"
    echo "        return x + $i;"
    echo "    }"
  done
  echo "}"
} > "$pkg_dir/domain/Untested.java"
expect_fail "untested code below the coverage floor" 'Coverage checks have not been met|covered ratio is' verify

[[ "$fails" -eq 0 ]] && echo "build-hygiene: all cases fail as expected" || { echo "build-hygiene: test FAILED"; exit 1; }
