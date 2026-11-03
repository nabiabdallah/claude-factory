#!/usr/bin/env bash
# Add Postgres persistence to a java-pipeline service. Run from the project root.
# Adds: JDBC/Flyway/Postgres/embedded-postgres dependencies, db/migration/V1, adapter/out/persistence,
# config/TransactionalUseCases, test support (@PostgresTest, DbLocks + embedded Postgres for every Spring test),
# datasource properties, compose.yaml, a CLAUDE.md section and an ADR. Then runs ./mvnw verify.
# It does not commit, and it does not edit ArchitectureTest (it prints the rule to add if it's missing).
set -euo pipefail

die() { echo "add-postgres: $*" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
files="$script_dir/../files"
helper="$script_dir/../../../bin/mvnw-sandboxed"
min_parent="1.1.0"

[[ -f pom.xml ]] || die "run from the project root (no pom.xml in $(pwd))"
grep -q '<artifactId>factory-parent</artifactId>' pom.xml || die "the project must inherit factory-parent"
if grep -q '<artifactId>flyway-database-postgresql</artifactId>' pom.xml; then
  die "Postgres is already set up (flyway-database-postgresql is in pom.xml)"
fi

app="$(grep -rl --include='*.java' '@SpringBootApplication' src/main/java 2>/dev/null | head -n 1 || true)"
[[ -n "$app" ]] || die "no @SpringBootApplication class under src/main/java"
pkg="$(sed -n 's/^package \([a-z0-9_.]*\);.*/\1/p' "$app" | head -n 1)"
[[ -n "$pkg" ]] || die "could not read the base package from $app"
name="$(sed -n 's|^  <artifactId>\(.*\)</artifactId>$|\1|p' pom.xml | head -n 1)"
[[ -n "$name" ]] || die "could not read the project artifactId from pom.xml"
db="${name//-/_}"
pkg_path="${pkg//.//}"

# Refuse to overwrite anything before changing a single file.
targets=(
  "src/main/java/$pkg_path/adapter/out/persistence/package-info.java"
  "src/main/java/$pkg_path/config/TransactionalUseCases.java"
  "src/main/resources/db/migration/V1__baseline.sql"
  "src/test/java/$pkg_path/support/EmbeddedPostgresInitializer.java"
  "src/test/java/$pkg_path/support/PostgresTest.java"
  "src/test/java/$pkg_path/support/PostgresSetupTest.java"
  "src/test/java/$pkg_path/config/TransactionalUseCasesTest.java"
  "src/test/resources/META-INF/spring.factories"
  "compose.yaml"
  "src/test/java/$pkg_path/support/DbLocks.java"
  "src/test/java/$pkg_path/support/DbLocksTest.java"
)
for t in "${targets[@]}"; do
  [[ ! -e "$t" ]] || die "$t already exists; refusing to overwrite"
done
# The readiness test needs Actuator (templates from java-pipeline 0.7.0 on have it).
readiness_test="src/test/java/$pkg_path/support/PostgresReadinessTest.java"
[[ ! -e "$readiness_test" ]] || die "$readiness_test already exists; refusing to overwrite"
if grep -qs '^spring.datasource.url' src/main/resources/application.properties; then
  die "src/main/resources/application.properties already sets spring.datasource.url"
fi

put() { # put <file under files/> <destination>
  mkdir -p "$(dirname "$2")"
  sed -e "s/__PKG__/${pkg}/g" -e "s/__DB__/${db}/g" "$files/$1" > "$2"
}

put main/adapter/out/persistence/package-info.java "${targets[0]}"
put main/config/TransactionalUseCases.java "${targets[1]}"
put main/db/migration/V1__baseline.sql "${targets[2]}"
put test/support/EmbeddedPostgresInitializer.java "${targets[3]}"
put test/support/PostgresTest.java "${targets[4]}"
put test/support/PostgresSetupTest.java "${targets[5]}"
put test/config/TransactionalUseCasesTest.java "${targets[6]}"
put test/resources/META-INF/spring.factories "${targets[7]}"
put compose.yaml "${targets[8]}"
put test/support/DbLocks.java "${targets[9]}"
put test/support/DbLocksTest.java "${targets[10]}"
if grep -q '<artifactId>spring-boot-starter-actuator</artifactId>' pom.xml; then
  put test/support/PostgresReadinessTest.java "$readiness_test"
fi

mkdir -p src/main/resources
props_tmp="$(mktemp "${TMPDIR:-/tmp}/add-postgres.XXXXXX")"
put main/application-datasource.properties "$props_tmp"
cat "$props_tmp" >> src/main/resources/application.properties
rm -f "$props_tmp"

# Dependencies (versions: Spring Boot for JDBC/Flyway/driver, factory-parent >= 1.1.0 for embedded Postgres).
python3 -I - pom.xml <<'PY'
import sys
path = sys.argv[1]
pom = open(path).read()
anchor = "  <dependencies>\n"
assert anchor in pom, "no <dependencies> block at project level"
deps = """  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-jdbc</artifactId>
    </dependency>
    <dependency>
      <groupId>org.flywaydb</groupId>
      <artifactId>flyway-database-postgresql</artifactId>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>postgresql</artifactId>
      <scope>runtime</scope>
    </dependency>
    <dependency>
      <groupId>io.zonky.test</groupId>
      <artifactId>embedded-postgres</artifactId>
      <scope>test</scope>
    </dependency>
"""
open(path, "w").write(pom.replace(anchor, deps, 1))
PY

parent_version="$(sed -n '/<parent>/,/<\/parent>/s|.*<version>\(.*\)</version>.*|\1|p' pom.xml | head -n 1)"
bumped=""
if [[ "$(printf '%s\n%s\n' "$min_parent" "$parent_version" | sort -V | head -n 1)" != "$min_parent" ]]; then
  sed -i "/<parent>/,/<\/parent>/s|<version>${parent_version}</version>|<version>${min_parent}</version>|" pom.xml
  bumped="factory-parent ${parent_version} -> ${min_parent} (needed for embedded Postgres versions)"
fi

if [[ -f CLAUDE.md ]]; then
  cat "$files/claude-md-section.md" >> CLAUDE.md
fi

mkdir -p docs/adr
last="$(ls docs/adr 2>/dev/null | sed -n 's/^\([0-9]\{4\}\)-.*/\1/p' | sort | tail -n 1)"
next="$(printf '%04d' $((10#${last:-0} + 1)))"
adr="docs/adr/${next}-postgres-jdbcclient-flyway-transactions.md"
sed -e "s/__NUM__/${next}/" -e "s/__DATE__/$(date +%F)/" "$files/adr.md" > "$adr"

# Find Java if the session was started without it (e.g. SDKMAN installed later).
if [[ -z "${JAVA_HOME:-}" ]] && ! command -v java >/dev/null 2>&1 && [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  set +u; source "$HOME/.sdkman/bin/sdkman-init.sh"; set -u
fi
"$helper" -q -B spotless:apply || die "spotless:apply failed"
"$helper" -q -B verify || die "./mvnw verify failed; changes left in place for inspection (not committed)"

echo "add-postgres: Postgres added to ${name} (package ${pkg}); ./mvnw verify green. Nothing committed."
[[ -n "$bumped" ]] && echo "add-postgres: ${bumped}"
echo "add-postgres: ADR ${adr}; local database: compose.yaml (docker compose up -d, outside the sandbox)."
if ! grep -rqs 'sql_only_in_persistence_adapters_and_config' src/test/java; then
  cat <<EOF
add-postgres: ArchitectureTest has no SQL-placement rule. Add this yourself (agents can't edit that file):

    @ArchTest
    static final ArchRule sql_only_in_persistence_adapters_and_config = noClasses()
            .that()
            .resideOutsideOfPackages("${pkg}.adapter.out.persistence..", "${pkg}.config..")
            .should()
            .dependOnClassesThat()
            .resideInAnyPackage("java.sql..", "javax.sql..", "org.springframework.jdbc..", "org.flywaydb..")
            .because("SQL, connections and migrations stay behind outbound persistence adapters");
EOF
fi
