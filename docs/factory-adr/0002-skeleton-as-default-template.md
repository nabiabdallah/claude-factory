# 0002. Default to an empty skeleton template; keep payments as an example

- Status: Accepted
- Date: 2026-11-03
- Deciders: Noel Abi Abdallah

## Context
`new-project` copied the agentic-java-starter as-is, so every new service started with the payments
sample: transfers, `Money`, idempotency rules and a payments-specific `CLAUDE.md`. Unrelated apps had
to delete code first, and agents read payments rules as if they applied. The starter is still useful
as a worked example of the patterns.

## Decision
Ship two templates. `skeleton` is the default: layer packages documented by `package-info.java`, the
`ErrorHandler` hardened during payments-service review (404/422 for domain errors, generic 500 with
`errorId` and a logged stack trace, no request path in problems), `ArchitectureTest`, a Spring
context test, CI and a domain-neutral `CLAUDE.md`. `payments-example` is the original starter,
chosen with `--template payments-example`. Each template declares its `base.package` and
`artifact.id` in `template.properties`, which `new-project` reads and removes from the copy.

In the skeleton, `archunit.properties` sets `archRule.failOnEmptyShould=false`, because a new
project has no classes in `application/` or `adapter/out/` and ArchUnit would fail those rules.
The rules themselves are unchanged and apply as soon as a layer has a class. A guard rule
(`guard_classes_are_imported`, `allowEmptyShould(false)`) must match the `Application` class, so
a setup that imports nothing, such as a bad package rename, still fails the build.

## Alternatives considered
- **Placeholder feature through every layer** (e.g. `GET /info`) — keeps ArchUnit fully strict, but
  every app starts with code to delete, which is the problem being solved.
- **Per-rule `allowEmptyShould(true)`** — explicit, but touches all seven rules for a concern that
  only exists while a project is new.
- **Strip the payments code inside `new-project`** — one template, but the script would have to know
  the example's file list and keep it in sync.

## Consequences
- Positive: new apps start domain-neutral; the payments example stays available for learning.
- Positive: adding a template (e.g. an event-driven service) is a directory plus `template.properties`.
- Negative: while a layer is empty, its rule passes without checking anything. The guard covers the
  total-failure case, not the case where one layer's package is misnamed.
- Follow-ups: decide whether `payments-example` should adopt the skeleton's `ErrorHandler` (it
  still maps any `IllegalArgumentException` to 400).
