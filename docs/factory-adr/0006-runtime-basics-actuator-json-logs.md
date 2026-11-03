# 0006. Runtime basics: health probes, JSON logs, graceful shutdown

- Status: Accepted
- Date: 2026-11-03
- Deciders: Noel Abi Abdallah

## Context
Services will run on Kubernetes (owner decision). They need liveness and readiness probes, logs that log
collectors can parse, and a clean stop. Actuator exposes much more than health by default if misconfigured,
and health details can leak internals.

## Decision
- Templates include `spring-boot-starter-actuator`, exposing **only** `health`, with the liveness and
  readiness groups enabled and `show-details` / `show-components` = never.
- `add-postgres` adds the database to the **readiness** group only: no traffic while Postgres is down, but
  no restarts of healthy pods because of a database outage.
- Console logs are **ECS JSON** by default (`logging.structured.format.console=ecs`); the `local` profile
  switches to plain text for development.
- `server.shutdown=graceful` with a 20s phase timeout.
- Tests: probes UP; health without components/details; `/env`, `/beans`, `/metrics`, `/configprops` not
  exposed; log lines are ECS JSON; the `local` profile turns structured logging off; readiness includes `db`.

## Alternatives considered
- **Separate management port** — isolates Actuator, but adds a second port to every manifest and probe;
  exposing health only on the main port is enough for now.
- **Plain-text logs by default, JSON in a `prod` profile** — friendlier locally, but a forgotten profile
  in production means unparseable logs; safe-by-default wins.

## Consequences
- Positive: every new service is probe-ready and emits structured logs with no extra work.
- Negative: local runs need `-Dspring-boot.run.profiles=local` for readable logs.
- Note: in a test JVM, Spring Boot configures logging once; the `local` profile test asserts the effective
  setting rather than log output (plain-text output was verified in an isolated run).
- Follow-ups: when auth arrives (release D), the health endpoints stay unauthenticated.
