#!/usr/bin/env bash
# Protect a java-pipeline service as an OAuth2 resource server (JWT). Run from the project root.
# Adds: the Boot 4 security-oauth2-resource-server starter + its test starter, config/SecurityConfig (health open, GET=read,
# rest=write), issuer/audience properties, test support (TestJwtInitializer, TestTokens, probe controller)
# and SecurityTest, a CLAUDE.md section and an ADR. Then runs ./mvnw verify. Does not commit.
set -euo pipefail

die() { echo "add-resource-server: $*" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
files="$script_dir/../files"
helper="$script_dir/../../../bin/mvnw-sandboxed"

[[ -f pom.xml ]] || die "run from the project root (no pom.xml in $(pwd))"
grep -q '<artifactId>factory-parent</artifactId>' pom.xml || die "the project must inherit factory-parent"
min_parent="2.0.0"
parent_version="$(sed -n '/<parent>/,/<\/parent>/s|.*<version>\(.*\)</version>.*|\1|p' pom.xml | head -n 1)"
if [[ "$(printf '%s\n%s\n' "$min_parent" "$parent_version" | sort -V | head -n 1)" != "$min_parent" ]]; then
  die "needs factory-parent >= ${min_parent} (Spring Boot 4); this project is on ${parent_version}. Upgrade it first (factory ADR 0010)"
fi
if grep -qE '<artifactId>spring-boot-starter-(security-)?oauth2-resource-server</artifactId>' pom.xml; then
  die "the resource server is already set up (an oauth2-resource-server starter is in pom.xml)"
fi
grep -q '<artifactId>spring-boot-starter-actuator</artifactId>' pom.xml \
  || die "needs spring-boot-starter-actuator (health probes stay open); add it first (java-pipeline 0.7.0+ templates have it)"

app="$(grep -rl --include='*.java' '@SpringBootApplication' src/main/java 2>/dev/null | head -n 1 || true)"
[[ -n "$app" ]] || die "no @SpringBootApplication class under src/main/java"
pkg="$(sed -n 's/^package \([a-z0-9_.]*\);.*/\1/p' "$app" | head -n 1)"
[[ -n "$pkg" ]] || die "could not read the base package from $app"
name="$(sed -n 's|^  <artifactId>\(.*\)</artifactId>$|\1|p' pom.xml | head -n 1)"
[[ -n "$name" ]] || die "could not read the project artifactId from pom.xml"
pkg_path="${pkg//.//}"
app_class="$(basename "$app" .java)"

targets=(
  "src/main/java/$pkg_path/config/SecurityConfig.java"
  "src/test/java/$pkg_path/support/TestJwtInitializer.java"
  "src/test/java/$pkg_path/support/TestTokens.java"
  "src/test/java/$pkg_path/support/SecurityProbeController.java"
  "src/test/java/$pkg_path/support/SecurityTest.java"
  "src/test/java/$pkg_path/support/IsolatedBootLogging.java"
  "src/test/java/$pkg_path/support/StartupGuardsTest.java"
  "src/test/java/$pkg_path/support/IdentityProviderTimeoutTest.java"
  "src/test/java/$pkg_path/config/IdentityProviderTransportTest.java"
)
# Runtime tests from java-pipeline 0.15.0+ templates (management port, factory ADR 0014): checked up front, so a
# project this script can't adapt is left untouched.
actuator_test="src/test/java/$pkg_path/runtime/ActuatorEndpointsTest.java"
observability_test="src/test/java/$pkg_path/runtime/ObservabilityTest.java"
grep -qs '^management.server.port=' src/main/resources/application.properties \
  || die "needs Actuator on its own management port (java-pipeline 0.15.0+ templates, factory ADR 0014)"
grep -qs 'var response = get(endpoint, null);' "$actuator_test" \
  || die "$actuator_test doesn't match the 0.15.0+ template (get(endpoint, null) in other_actuator_endpoints_are_not_exposed)"
grep -qs 'return null; // no API authentication yet' "$observability_test" \
  || die "$observability_test doesn't match the 0.15.0+ template (apiAuthorization() returning null)"

for t in "${targets[@]}"; do
  [[ ! -e "$t" ]] || die "$t already exists; refusing to overwrite"
done
if grep -qs '^spring.security.oauth2.resourceserver' src/main/resources/application.properties; then
  die "src/main/resources/application.properties already configures spring.security.oauth2.resourceserver"
fi

put() { # put <file under files/> <destination>
  mkdir -p "$(dirname "$2")"
  sed -e "s/__PKG__/${pkg}/g" -e "s/__SVC__/${name}/g" -e "s/__APP__/${app_class}/g" "$files/$1" > "$2"
}

put main/config/SecurityConfig.java "${targets[0]}"
put test/support/TestJwtInitializer.java "${targets[1]}"
put test/support/TestTokens.java "${targets[2]}"
put test/support/SecurityProbeController.java "${targets[3]}"
put test/support/SecurityTest.java "${targets[4]}"
put test/support/IsolatedBootLogging.java "${targets[5]}"
put test/support/StartupGuardsTest.java "${targets[6]}"
put test/support/IdentityProviderTimeoutTest.java "${targets[7]}"
put test/config/IdentityProviderTransportTest.java "${targets[8]}"

# The templates' runtime tests call actuator and the API without a token (factory ADR 0014). Behind the resource
# server: ActuatorEndpointsTest sends a token where it proves "not exposed" (exactly 404) and gains a tokenless 401
# case, never "401 or 404" (which would hide a regression to exposure.include=*); ObservabilityTest's API calls
# send a read token. Both were checked before any file changed.
python3 -I - "$actuator_test" "$observability_test" "$name" "$pkg" <<'PYA'
import sys
actuator, observability, svc, pkg = sys.argv[1:]
s = open(actuator).read()
old = """        // Exactly 404. /java-pipeline:add-resource-server sends a token here and adds a tokenless 401 case.
        var response = get(endpoint, null);

        assertThat(response.statusCode()).isEqualTo(404);
        assertThat(response.body()).doesNotContain("propertySources");
    }
"""
new = """        // With a valid token: exactly 404 proves the endpoint is not exposed.
        var response = get(endpoint, TestTokens.withScopes("%s:read"));

        assertThat(response.statusCode()).isEqualTo(404);
        assertThat(response.body()).doesNotContain("propertySources");
    }

    @ParameterizedTest
    @ValueSource(strings = {"/actuator/env", "/actuator/beans", "/actuator/metrics", "/actuator/configprops"})
    void other_actuator_endpoints_need_a_token(String endpoint) throws Exception {
        var response = get(endpoint, null);

        assertThat(response.statusCode()).isEqualTo(401);
        assertThat(response.body()).doesNotContain("propertySources");
    }
""" % svc
s = s.replace(old, new, 1)
s = s.replace("import java.net.URI;", "import %s.support.TestTokens;\nimport java.net.URI;" % pkg, 1)
open(actuator, "w").write(s)
s = open(observability).read()
s = s.replace("        return null; // no API authentication yet",
              '        return TestTokens.withScopes("%s:read");' % svc, 1)
s = s.replace("import io.opentelemetry.sdk.testing", "import %s.support.TestTokens;\nimport io.opentelemetry.sdk.testing" % pkg, 1)
open(observability, "w").write(s)
PYA

mkdir -p src/main/resources
props_tmp="$(mktemp "${TMPDIR:-/tmp}/add-resource-server.XXXXXX")"
put main/application-security.properties "$props_tmp"
cat "$props_tmp" >> src/main/resources/application.properties
rm -f "$props_tmp"

# Register the test key initializer next to any existing one (e.g. add-postgres' EmbeddedPostgresInitializer).
factories="src/test/resources/META-INF/spring.factories"
mkdir -p "$(dirname "$factories")"
python3 -I - "$factories" "$pkg.support.TestJwtInitializer" <<'PY'
import sys, os
path, initializer = sys.argv[1], sys.argv[2]
key = "org.springframework.context.ApplicationContextInitializer"
lines = open(path).read().splitlines() if os.path.exists(path) else []
for i, line in enumerate(lines):
    if line.startswith(key + "="):
        lines[i] = line.rstrip() + "," + initializer
        break
else:
    lines += ["# Every Spring test context validates tokens against a throwaway key (no IdP needed).",
              key + "=" + initializer]
open(path, "w").write("\n".join(lines) + "\n")
PY

python3 -I - pom.xml <<'PY'
import sys
path = sys.argv[1]
pom = open(path).read()
anchor = "  <dependencies>\n"
assert anchor in pom, "no <dependencies> block at project level"
deps = """  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-security-oauth2-resource-server</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-security-oauth2-resource-server-test</artifactId>
      <scope>test</scope>
    </dependency>
"""
open(path, "w").write(pom.replace(anchor, deps, 1))
PY

if [[ -f CLAUDE.md ]]; then
  sed -e "s/__SVC__/${name}/g" "$files/claude-md-section.md" >> CLAUDE.md
fi

mkdir -p docs/adr
last="$(ls docs/adr 2>/dev/null | sed -n 's/^\([0-9]\{4\}\)-.*/\1/p' | sort | tail -n 1)"
next="$(printf '%04d' $((10#${last:-0} + 1)))"
adr="docs/adr/${next}-oauth2-resource-server-jwt.md"
sed -e "s/__NUM__/${next}/" -e "s/__DATE__/$(date +%F)/" -e "s/__SVC__/${name}/g" "$files/adr.md" > "$adr"

if [[ -z "${JAVA_HOME:-}" ]] && ! command -v java >/dev/null 2>&1 && [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  set +u; source "$HOME/.sdkman/bin/sdkman-init.sh"; set -u
fi
"$helper" -q -B spotless:apply || die "spotless:apply failed"
if ! "$helper" -q -B verify; then
  cat >&2 <<EOT
add-resource-server: ./mvnw verify failed; changes left in place (not committed).
add-resource-server: expected for an existing service: endpoint tests that call without a token now get 401.
add-resource-server: send TestTokens.withScopes("${name}:read" / "${name}:write") in those tests (see CLAUDE.md).
EOT
  exit 1
fi

echo "add-resource-server: ${name} is now an OAuth2 resource server (scopes ${name}:read / ${name}:write); ./mvnw verify green. Nothing committed."
echo "add-resource-server: ADR ${adr}. Production needs AUTH_ISSUER_URI (and AUTH_AUDIENCE if not '${name}')."
