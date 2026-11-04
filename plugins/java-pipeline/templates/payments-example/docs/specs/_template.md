# Spec: <feature name>

- Status: Draft | Approved
- Owner: <you>
- Related ADRs: <links or "none">

## Problem
Who needs this and why. 2–5 sentences. No solution yet.

## Scope
**In:**
- ...

**Out (explicitly not doing):**
- ...

## Contract
API / event / file format the outside world sees. Paste or link the OpenAPI / AsyncAPI
fragment, or define request/response records here. Agents implement against this — get it right first.

## Authorization
Who may call this (scopes), whose data each operation touches, and what a caller sees for data that isn't
theirs (normally the same as "not found"). "Anyone with the scope, any data" must be stated, not implied.

## Acceptance criteria
Numbered, testable, one behaviour each. The test-writer agent maps one or more tests to each.
1. Given ..., when ..., then ...
2. ...

## Failure modes
What happens on: invalid input, unknown entity, downstream timeout, duplicate request,
partial failure, another caller's data. Expected status codes / error types.

## Non-functional
Latency, volume, audit/logging requirements, PII constraints, data retention.

## Open questions
- ...
