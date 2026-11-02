---
name: new-project
argument-hint: <project-name> <base.package>
description: Create a new Spring Boot hexagonal service in ~/dev/projects from the java-pipeline template (renames the package everywhere, git init, ./mvnw verify, first commit). Use when the user asks to start, create or scaffold a new Java project or service.
disable-model-invocation: true
---

# New project

Arguments: $ARGUMENTS

1. Parse two arguments: a kebab-case project name (e.g. `payments-service`) and a base
   Java package (e.g. `com.example.payments`). If either is missing or malformed, ask the
   user; do not guess.
2. Run the scaffolding script exactly once:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/new-project/scripts/new-project.sh" <project-name> <base.package>
   ```

   It copies `${CLAUDE_PLUGIN_ROOT}/templates/spring-service` to `~/dev/projects/<project-name>`,
   moves the sources to the new package, rewrites every package reference (including the
   constants in `ArchitectureTest`), sets the Maven `groupId`/`artifactId`, runs `git init`,
   `./mvnw verify`, and makes the first commit. It refuses to overwrite an existing directory.
3. If the script fails, report its error output verbatim. Do not patch the template, weaken
   `ArchitectureTest`, or delete tests to get it green.
4. On success, report the path, the package, the commit hash, and the next step:
   `cd ~/dev/projects/<project-name> && claude`, then `/java-pipeline:new-feature ...`.
