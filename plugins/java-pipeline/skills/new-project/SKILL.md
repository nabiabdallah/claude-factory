---
name: new-project
argument-hint: <project-name> <base.package> [--template <name>]
description: Create a new Spring Boot hexagonal service in ~/dev/projects from a java-pipeline template (default: an empty skeleton; optionally the payments example). Renames the package everywhere, git init, ./mvnw verify, first commit. Use when the user asks to start, create or scaffold a new Java project or service.
disable-model-invocation: true
---

# New project

Arguments: $ARGUMENTS

1. Parse the arguments: a kebab-case project name (e.g. `customer-service`), a base Java package
   (e.g. `com.example.customers`), and optionally `--template <name>`. If the name or package is
   missing or malformed, ask the user; do not guess.
2. Templates (list them with the script's `--list` if the user asks which exist):
   - `skeleton` (default): empty layers, `ErrorHandler`, `ArchitectureTest`, Spring context test, CI.
     Use it unless the user asks for the example.
   - `payments-example`: the skeleton plus a worked payments domain (transfers, `Money`,
     idempotency). For learning the patterns, not as a base for unrelated apps.
3. Run the scaffolding script exactly once:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/new-project/scripts/new-project.sh" [--template <name>] <project-name> <base.package>
   ```

   It copies `${CLAUDE_PLUGIN_ROOT}/templates/<name>` to `~/dev/projects/<project-name>`, moves the
   sources to the new package, rewrites every package reference (including the constants in
   `ArchitectureTest`), names the project after `<project-name>` (Maven `artifactId`, application
   name), runs `git init` and `./mvnw verify`, and makes the first commit. It refuses to overwrite an
   existing directory.
4. If the script fails, report its error output verbatim. Do not patch the template, weaken
   `ArchitectureTest`, or delete tests to get it green.
5. On success, report the path, the template, the package, the commit hash, and the next step:
   `cd ~/dev/projects/<project-name> && claude`, then `/java-pipeline:new-feature ...`.
