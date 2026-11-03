# Service — Agent Guide

Spring Boot service, Java 21, Maven wrapper. Hexagonal (ports & adapters) architecture.
Pipeline (agents, skills, hooks) comes from the `java-pipeline` plugin — not from this repo's `.claude/`.

## Commands
- Build + all gates: `mvnw-sandboxed -q verify` (plugin helper: `./mvnw` + sandbox proxy; same args)
- Unit tests only: `mvnw-sandboxed -q test`
- One test class: `mvnw-sandboxed -q test -Dtest=TransferMoneyServiceTest`
- Format: `mvnw-sandboxed -q spotless:apply`
- Run locally: `./mvnw spring-boot:run -Dspring-boot.run.profiles=local` (plain-text logs; default is ECS JSON)
- Health: `/actuator/health/liveness`, `/actuator/health/readiness` (only health is exposed)

- Image: built and pushed by CI on `main` only (Jib); don't add a Dockerfile. Manifests: `deploy/k8s/`.

## Architecture (enforced by `ArchitectureTest` — the build fails if you break it)
```
com.example.payments
├── domain/                  pure Java: entities, value objects, domain exceptions. NO framework imports.
├── application/
│   ├── port/in/             use-case interfaces + command records
│   ├── port/out/            interfaces the app needs (repositories, gateways)
│   └── *Service             use-case implementations. NO Spring, NO adapter imports.
├── adapter/in/web/          REST controllers → call port/in only
├── adapter/out/persistence/ implementations of port/out
└── config/                  Spring wiring (@Configuration). Only place that knows everything.
```

## Rules
- Money is `Money` (BigDecimal + currency). Never `double`/`float` for amounts.
- Domain rule violations throw a domain exception; the web adapter maps it to an HTTP status.
- New external integration = new port in `port/out` + adapter in `adapter/out/<name>`. Never call an external system from `application` or `domain`.
- Idempotency: any operation that moves money takes a client-supplied idempotency key.
- Never log full account numbers, amounts with customer identifiers, or tokens.
- Tests first. Every use case has a unit test with an in-memory adapter; no Spring context in unit tests.

## Workflow
1. Start features with `/java-pipeline:new-feature`. Every feature starts from a spec in `docs/specs/` (copy `_template.md`). No spec → ask for one.
2. Plan before coding; get the plan reviewed by the `java-pipeline:architect-reviewer` agent.
3. Work is done only when `./mvnw verify` passes — the plugin's Stop hook enforces this.
4. Significant design decisions → an ADR in `docs/adr/` (use `/java-pipeline:write-adr`).

## Don't
- Don't edit `ArchitectureTest` to make a build pass. If a rule is wrong, stop and say so.
- Don't add dependencies without stating why in the plan.
- Don't read `.env` or anything under `secrets/`.
- Stage files by path when committing; never `git add -A` / `git add .` (sandbox placeholders under `.claude/` break it).
