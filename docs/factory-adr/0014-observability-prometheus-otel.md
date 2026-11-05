# 0014. Observability: Actuator on a management port, Prometheus metrics, OpenTelemetry traces

- Status: Accepted
- Date: 2026-11-05
- Deciders: Noel Abi Abdallah

## Context
Services exposed only `/actuator/health` (ADR 0006): nothing to alert on (latency, errors, JVM), no traces
across services, and no way to join log lines to a request. The owner chose Prometheus + OpenTelemetry over OTLP
(vendor-neutral) as the stack.

## Decision
In both templates (java-pipeline 0.15.0; factory-parent unchanged):
- **Management port.** `management.server.port=8081` (container port `management`); exposure `health,prometheus`
  only. Port 8080 serves only the API, so an ingress routing to `http` can't expose Actuator whatever its path
  rules. Probes moved to `management`. The NetworkPolicy admits `management` only from namespaces labelled
  `claude-factory/monitoring=true` (kubelet probes aren't subject to it).
- **Metrics.** `micrometer-registry-prometheus` (version from Spring Boot) on `/actuator/prometheus`; common tag
  `application=<service>`; `http.server.requests` percentile histograms for latency SLOs; HTTP metrics are tagged
  with the URI template. Pods carry the `prometheus.io/scrape|port|path` annotations.
- **Traces.** `spring-boot-starter-opentelemetry` (Boot 4: OTel SDK, Micrometer Tracing bridge, OTLP exporter),
  with OkHttp excluded and `opentelemetry-exporter-sender-jdk` used instead (no OkHttp/Kotlin in the image). Its
  OTLP metrics registry is off (`management.otlp.metrics.export.enabled=false`): Prometheus is the one metrics path.
  The OTLP endpoint is unset in `application.properties`, so local runs and tests export nothing; the base
  Deployment sets `MANAGEMENT_OPENTELEMETRY_TRACING_EXPORT_OTLP_ENDPOINT` to the placeholder
  `http://otel-collector.monitoring:4318/v1/traces`. Overlays set sampling (staging `1.0`, prod `0.1`) and
  `OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=<env>`. NetworkPolicy egress: TCP 4317/4318 to
  `claude-factory/monitoring` namespaces. W3C `traceparent` in and out (B3 also accepted).
- **No identifiers in traces.** Micrometer copies the raw request URL into spans as `http.url`
  (`/probe/CUST-000123456`, seen in the mutation run). `config/ObservabilityConfig` registers an
  `ObservationFilter` that removes `http.url` from every observation; spans keep the URI template.
- **Logs.** ECS JSON logs carry `traceId` and `spanId` from the current span.
- **Tests.** `ObservabilityTest` (real ports): Prometheus text on the management port with the URI template, the
  application tag and histogram buckets, and no raw id; no Actuator on the app port; a request with `traceparent`
  yields a server span in that trace with no attribute containing the id, and a log line with the trace id; no
  OTLP metrics registry and no OTLP span exporter while no endpoint is set. `ActuatorEndpointsTest` moved to the
  management port. Removing the filter makes the trace test fail.
- **add-resource-server.** The management port shares the security filter chain, so `/actuator/prometheus` is
  permitted with health (it exists only on the management port). The script now requires the 0.15.0+ runtime
  tests and refuses before changing anything otherwise; it makes `ObservabilityTest` send a read token and turns
  the "not exposed" case into token → 404 plus tokenless → 401. Its probe checks moved to the management port.
- **Factory CI** checks each rendered overlay for the management port on all probes and the NetworkPolicy, both
  monitoring rules, and the sampling variable.

## Alternatives considered
- **Prometheus endpoint on the app port** — one port fewer, but exposure would then depend on every ingress's
  path rules.
- **OTLP for metrics too** — fewer open ports, but needs a Collector everywhere, also for metrics; owner chose
  Prometheus scraping.
- **A PodMonitor/ServiceMonitor** — needs the Prometheus Operator's CRDs, which have no schema in kubeconform's
  default set; annotations work with the common discovery config. Follow-up.
- **Keeping OkHttp** — the starter's default sender, but it adds OkHttp and the Kotlin stdlib to every image.

## Consequences
- Positive: every service gets metrics, traces and log correlation from the template, and no Actuator endpoint is
  reachable through the API port.
- Negative: two ports per pod; probes and scrapers must use `management`.
- Negative: the Collector address is a placeholder until a cluster exists; until then spans are dropped (the
  exporter logs failures).
- Negative: `OTEL_RESOURCE_ATTRIBUTES` relies on Spring Boot's OTel environment mapping
  (`management.opentelemetry.map-environment-variables`, default on); it isn't exercised by a test.
- Negative: existing services (payments-service) don't get this automatically; add-resource-server now needs the
  0.15.0+ templates.
- Follow-ups: dashboards and alerts, PodMonitor, JDBC/outbound client spans, exemplars, OTel logs.
- Amends ADR 0006 ("only health is exposed").
