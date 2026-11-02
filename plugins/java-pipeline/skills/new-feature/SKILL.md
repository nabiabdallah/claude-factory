---
name: new-feature
argument-hint: <feature description>
description: Run the full spec → plan → review → TDD → verify → review pipeline for a new feature. Use when the user asks to build or add a feature, endpoint, use case or integration.
---

# New feature pipeline

Feature request: $ARGUMENTS

Follow these stages in order. Do not skip a stage; stop and ask the user if one can't be completed.

## 1. Spec
- Find the spec in `docs/specs/`. If none exists, draft one from `docs/specs/_template.md`
  with the user, and STOP for their approval before planning.
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

## 6. Review
- Delegate to the `java-pipeline:code-reviewer` agent. Fix every MUST FIX item, then re-run `mvnw-sandboxed -q verify`.

## 7. Hand-off
- Commit on a feature branch with a message referencing the spec.
- Report to the user: what was built, acceptance criteria → tests mapping,
  reviewer findings you fixed, anything deferred, and whether an ADR was written.
