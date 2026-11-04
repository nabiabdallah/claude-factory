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

# The templates' ActuatorEndpointsTest expects 404 for unexposed endpoints without a token; behind the resource
# server that request is a 401 first. Rewrite it into two exact cases (token → 404 proves "not exposed";
# no token → 401), never "401 or 404" (which would hide a regression to exposure.include=*).
actuator_test="src/test/java/$pkg_path/runtime/ActuatorEndpointsTest.java"
actuator_note=""
if [[ -f "$actuator_test" ]]; then
  if ! python3 -I - "$actuator_test" "$name" <<'PYA'
import sys
path, svc = sys.argv[1], sys.argv[2]
s = open(path).read()
old = """        mvc.perform(get(endpoint))
                .andExpect(status().isNotFound())
                .andExpect(content().string(not(containsString("propertySources"))));
    }"""
if old not in s:
    sys.exit(1)
new = """        // With a valid token: exactly 404 proves the endpoint is not exposed.
        mvc.perform(get(endpoint).header("Authorization", TestTokens.withScopes("%s:read")))
                .andExpect(status().isNotFound())
                .andExpect(content().string(not(containsString("propertySources"))));
    }

    @ParameterizedTest
    @ValueSource(strings = {"/actuator/env", "/actuator/beans", "/actuator/metrics", "/actuator/configprops"})
    void other_actuator_endpoints_need_a_token(String endpoint) throws Exception {
        mvc.perform(get(endpoint))
                .andExpect(status().isUnauthorized())
                .andExpect(content().string(not(containsString("propertySources"))));
    }""" % svc
s = s.replace(old, new, 1)
pkg_line = s.splitlines()[0]
base = pkg_line.removeprefix("package ").removesuffix(";").rsplit(".runtime", 1)[0]
s = s.replace("import org.junit.jupiter.api.Test;", "import " + base + ".support.TestTokens;\nimport org.junit.jupiter.api.Test;", 1)
open(path, "w").write(s)
PYA
  then
    actuator_note="add-resource-server: $actuator_test doesn't match the template; make 'other_actuator_endpoints_are_not_exposed' send TestTokens.withScopes(\"${name}:read\") (expect 404) and add a tokenless case expecting 401."
  fi
fi

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
${actuator_note}
add-resource-server: send TestTokens.withScopes("${name}:read" / "${name}:write") in those tests (see CLAUDE.md).
EOT
  exit 1
fi

echo "add-resource-server: ${name} is now an OAuth2 resource server (scopes ${name}:read / ${name}:write); ./mvnw verify green. Nothing committed."
echo "add-resource-server: ADR ${adr}. Production needs AUTH_ISSUER_URI (and AUTH_AUDIENCE if not '${name}')."
if [[ -n "$actuator_note" ]]; then
  echo "$actuator_note"
fi
