# 16 — Observability

You cannot scale, debug, or trust a 10-microservice event-driven system you cannot see. **Observability is mandatory from day one** — without it, debugging across services and async event hops is impossible.

## The four signals we collect

| Signal | Question it answers | Tool |
|---|---|---|
| **Logs** | What happened? | Grafana Loki |
| **Metrics** | How much, how often, how fast? | Prometheus + Grafana |
| **Traces** | Why was *this specific request* slow? | OpenTelemetry → Tempo |
| **Errors** | Did something just break? | Sentry |

Plus: **uptime monitoring** (UptimeRobot) and **synthetic checks** for critical user flows.

## Logs

Every service writes structured JSON logs to stdout. The container runtime ships them to Loki via a log collector (Promtail or Vector).

Each log line includes:

- Timestamp
- Level (`info`, `warn`, `error`)
- Service name (`core-api`, `chat`, `parser`)
- `request_id` (the X-Request-ID injected by Kong)
- `user_id` (if authenticated)
- Message
- Structured fields (whatever's relevant)

**Searchable in Grafana** by any of these fields. When a user reports a bug, ask for the request-ID from their dev tools and trace it across all services in seconds.

## Metrics — what we track

**API metrics (per service):**
- Request rate (requests/sec)
- Latency p50/p95/p99
- Error rate (% of 5xx responses)
- In-flight requests

**Business metrics:**
- New signups (per role, per hour)
- New job posts per hour
- Applications per hour
- Active subscriptions
- Revenue (from Stripe)

**System metrics:**
- CPU, memory, disk per pod
- Postgres query latency, slow queries, connections
- Redis command rate, memory, evictions
- Queue depth and worker throughput
- WebSocket connections

All visible in Grafana dashboards.

## Traces

A trace follows one request from Cloudflare → Kong → Core API → Postgres → Resume Parser → ... showing the latency of each hop.

Instrumentation: **OpenTelemetry SDK** in each service (Laravel, Python, Node). Auto-instrumented for HTTP and DB calls. Manual spans around interesting blocks.

Sample 10% of requests in production (don't trace everything — costly). Sample 100% on errors.

## Errors

Sentry captures exceptions automatically:

- Stack trace
- Request context (URL, headers, body)
- User ID
- Breadcrumbs (recent log lines leading up to the error)

One Sentry project per service. Errors deduplicated by stack signature so a single bug producing 10,000 events is one ticket.

Alerts in Slack when:

- A new (never-seen-before) error appears
- An error spikes 10× in 5 minutes
- A regression of a previously-resolved issue

## Alerts — only for what's actionable

**Page-on-call (PagerDuty-style):**
- Any service down >2 minutes
- Error rate >5% for >5 minutes
- Database primary unreachable
- Queue depth >100K (jobs piling up)

**Slack channel (look-when-convenient):**
- Sentry new error
- High latency (p95 > 1 second for 10 minutes)
- Disk usage >80%
- Subscription expiry sweeper failed
- ClamAV down

**Email (digest):**
- Daily summary of platform metrics

The mistake to avoid: alerting on everything. Each alert dilutes attention. **Every alert should map to a runbook** — if the on-call person can't act on it, it shouldn't page them.

## Health checks

Every service exposes:

- `GET /health/live` — "I'm running" (no dependencies checked)
- `GET /health/ready` — "I can serve traffic" (DB, Redis reachable)

Kubernetes uses these for liveness and readiness probes; Kong uses them for routing decisions; UptimeRobot pings them externally.

## Tracing across async event hops

Every Kafka event payload includes the `request_id` from the originating HTTP request. Every consumer logs and emits new spans with the same `request_id`. So one user's apply action shows up in logs with the **same trace ID** across:

- Kong (received the request)
- Jobs Service (validated + inserted application + outbox row)
- Outbox publisher (event published to Kafka)
- Notification Service (FCM + email dispatched)
- Resume Parser Service (resume processed)
- Search Service (count updated)
- Chat Service (WebSocket badge pushed)

One ID, full journey, including async hops. This is the killer feature of OpenTelemetry-instrumented event-driven systems.

## Schema registry and event contract observability

Every event published to Kafka is validated against its registered schema. Violations:

- Block the producer (caught in CI)
- Get logged when consumers see incompatible payloads
- Surface in a Grafana dashboard tracking schema-version distribution per topic

This catches "team X added a field that broke team Y" before it affects users.

## Where the observability stack runs

**Production:**
- Loki + Prometheus + Grafana + Tempo on a dedicated K8s namespace
- Or managed equivalents (Grafana Cloud, Datadog, etc.)

**Local dev:**
- Lightweight: Grafana + Loki + Prometheus + Tempo run in `docker-compose` so devs can use the same dashboards as production
- All services emit OpenTelemetry traces locally too — same instrumentation, fewer hops

## Synthetic monitoring

A simple script runs every 5 minutes (UptimeRobot or a K8s CronJob):

- Hit the homepage → expect 200
- Log into a test admin account → expect success
- Browse jobs → expect ≥1 result
- Apply to a test job → expect 200 or 409 (already applied)

If any of these fail, page on-call. **Synthetic monitoring catches broken user flows that internal metrics miss** (e.g., a frontend deploy that broke the apply form — the API is healthy, but the user can't submit).

## Kafka-specific observability

Critical metrics for the event bus:

- **Consumer lag per group per topic** — alert if >1 minute on hot topics
- **Event publish rate** per topic
- **Outbox depth** per service — alert if growing (publisher can't keep up)
- **DLQ depth** per consumer group — alert on any
- **Schema validation failures** — alert immediately
- **Broker disk usage** — alert before retention forces purge

A Grafana dashboard with these is the first thing on-call checks during an incident.

## What good looks like

In production, when something goes wrong, you should be able to answer **all of these in under 5 minutes**:

- What broke?
- When did it start?
- How many users are affected?
- Which service is the root cause?
- What's the most recent change that could have caused it?

If you can't, your observability is broken — fix it before fixing the bug.
