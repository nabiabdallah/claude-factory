---
name: new-feature
argument-hint: <feature description>
description: Run the full spec → plan → review → TDD → verify → review pipeline for a new feature. Use when the user asks to build or add a feature, endpoint, use case or integration.
---

# New feature pipeline

Feature request: $ARGUMENTS

Follow these stages in order. Do not skip a stage; stop and ask the user if one can't be completed.

## Headless runs
When `FACTORY_HEADLESS=1` (an unattended run started by `.github/workflows/factory-feature.yml`, factory ADR 0018)
nobody can answer a question or approve anything. The stages below still apply, with these changes:
- **Spec:** the request names it. It is already approved; never draft, edit or reinterpret a spec. If it is
  unclear, contradicts itself or the code, or can't be met, stop: write what is missing to the report file and
  end without committing. The run then fails and the owner fixes the spec.
- **Plan:** don't wait for approval. Resubmit to the architect-reviewer at most twice; if the verdict is still
  REJECT, stop the same way. The final plan and verdict go in the report.
- **Hand-off:** commit on the branch you are on (the runner created it). Don't push, don't open a PR, don't
  switch branches. Leave no uncommitted or untracked files. Write the stage 7 report as Markdown to the path in
  `$FACTORY_REPORT`: it becomes the pull request description.
- **Off limits:** `.github/`, `.claude/`, `CLAUDE.md`, `docs/specs/`, `ArchitectureTest`, `archunit.properties`,
  `mvnw`, `.mvn/`, `.gitignore`, `.trivyignore.yaml`, `deploy/k8s/overlays/`, and anything in `pom.xml` that
  loosens a build rule. The runner refuses the whole run if one changes. If the feature truly needs such a
  change, say so in the report instead of making it.
- The runner runs `./mvnw verify` itself after you finish; a red build fails the run whatever you reported.

## 1. Spec
- Find the spec in `docs/specs/`. If none exists, draft one with the `java-pipeline:intake` skill (it fills
  `docs/specs/_template.md` and lists open questions), and STOP for the user's approval before planning.
- The spec must have numbered acceptance criteria. If it doesn't, ask.

## 2. Plan
- Write a short plan: classes per package, ports added or reused, contract changes,
  new dependencies (with reason), test list mapped to acceptance criteria.
- Delegate the plan to the `java-pipeline:architect-reviewer` agent.
- Address every BLOCKING item. If the verdict is REJECT, revise and resubmit.
- Show the user the final plan and the verdict. Wait for approval if anything non-trivial changed.

## 3. Red
- Delegate to the `java-pipeline:test-writer` agent with the spec path and the approved plan.
- Confirm the new tests fail for the expected reason.

## 4. Green
- Implement the smallest code that makes the tests pass, layer by layer:
  domain → ports → service → adapters → config wiring.
- Run `mvnw-sandboxed -q test` after each layer.

## 5. Verify
- Run `mvnw-sandboxed -q verify` (tests + ArchUnit + formatting). Fix the cause of any failure;
  never edit `ArchitectureTest` or delete a test to go green.
- Run it yourself even though the Stop hook also does: the hook only acts on the project the session was
  started in.
- **Mutation-check critical safeguards** (locking, lock order, transactions, idempotency, authorisation and ownership checks):
  for each one, temporarily remove or break it in production code, run the matching tests, and confirm at
  least one fails; then restore the code and confirm it is byte-identical to before (keep a backup). A
  mutation must really remove the protection — e.g. locking in a *different but consistent* order is not a
  lock-order mutation; locking in request order is. If a mutation survives, the tests are missing
  something: add or fix a test (not production code) until it is caught.

## 6. Review
- Delegate to the `java-pipeline:code-reviewer` agent. Fix every MUST FIX item, then re-run `mvnw-sandboxed -q verify`.

## 7. Hand-off
- Commit on a feature branch with a message referencing the spec. Stage files by path
  (`git add src/... docs/...`); never `git add -A` or `git add .` — inside the sandbox those
  pick up `/dev/null` placeholders under `.claude/` and fail.
- Report to the user: what was built, acceptance criteria → tests mapping, mutation checks and their
  results, reviewer findings you fixed, anything deferred, and whether an ADR was written. Put the same
  in the PR description.
