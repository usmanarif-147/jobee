# 22 — Event Bus & Pub/Sub (Kafka)

The spine of the system. Every meaningful change in any service is **published as an event** to Kafka. Other services that care subscribe to the relevant topic. Services do not call each other for side effects — they emit events and let consumers react.

This file is the dedicated reference. Other files link here when they touch events.

## Why event-driven, not service-to-service calls

A naive design has Jobs Service call Notification Service, Resume Parser, and Search Service directly when an application is created. Three problems:

1. **Tight coupling** — Jobs Service must know about every consumer.
2. **Cascading failures** — if Notification Service is down, the whole apply request fails.
3. **No replay** — if a consumer was buggy, you can't re-run the past hour of events.

Pub/sub fixes all three. Jobs Service emits one event. Whoever cares listens. Consumers can be added or removed without touching the producer.

## The tool: Apache Kafka

Why Kafka:

- Append-only log — every event is stored durably and ordered within a partition
- Multiple independent consumer groups (different services consuming the same topic at different speeds)
- Replay from any point in the topic
- Massive throughput, horizontal scaling
- Industry standard

Kafka cluster: minimum 3 brokers in production for fault tolerance. Local dev: 1 broker is enough.

## The mental model

```
   Producer service (e.g., Jobs Service)
              │
              ▼
   ┌────────────────────────────┐
   │  Kafka topic "applications"│  ← partitions, durable storage
   └─────────────┬──────────────┘
                 │
   ┌─────────────┼──────────────┬──────────────┐
   ▼             ▼              ▼              ▼
 Notification  Resume         Search         Reporting
 Service       Parser         Service        Service
 (consumer     (consumer      (consumer      (consumer
  group A)      group B)       group C)       group D)
```

Each consumer group **independently** tracks its position in the topic. Notification Service can be 5 events behind; Search Service can be live — they don't block each other.

## Topics — designed by domain entity, not by consumer

One topic per domain object. Each topic carries multiple event types for that object.

| Topic | Producer | Event types |
|---|---|---|
| `identity.users` | Identity Service | `UserRegistered`, `UserEmailVerified`, `UserDeleted` |
| `companies.companies` | Companies Service | `CompanyRegistered`, `CompanyUpdated`, `CompanyUserAdded` |
| `jobs.jobs` | Jobs Service | `JobCreated`, `JobUpdated`, `JobClosed` |
| `jobs.applications` | Jobs Service | `ApplicationCreated`, `ApplicationStatusChanged`, `ApplicationWithdrawn` |
| `payments.subscriptions` | Payment Service | `SubscriptionActivated`, `PaymentFailed`, `SubscriptionExpired` |
| `chat.messages` | Chat Service | `MessageSent`, `MessageDeleted` (rarely needed by other services) |
| `media.files` | Media Service | `FileUploaded`, `FileScanClean`, `FileScanInfected`, `FileDeleted` |
| `parsing.resumes` | Resume Parser | `ResumeParsed`, `ResumeParseFailed` |

Naming convention: `{service}.{entity}` — easy to grep, easy to set ACLs.

## Anatomy of an event

Every event has the same envelope:

```
{
  "event_id":     "uuid",
  "event_type":   "ApplicationCreated",
  "schema_version": 2,
  "occurred_at":  "ISO timestamp",
  "request_id":   "for distributed tracing",
  "producer":     "jobs-service",
  "payload":      { ...domain-specific fields... }
}
```

`event_id` allows consumers to deduplicate (Kafka can deliver the same event twice during failover).
`schema_version` allows graceful evolution of payloads.
`request_id` carries the trace through every hop.

## Schema Registry — non-negotiable

When ten services share events, you need a contract. Every event type is defined in a **schema** (JSON Schema, Avro, or Protobuf), versioned, and stored in a **Schema Registry** (Confluent's, or Karapace as the open-source option).

Rules:

- Producers register a schema for each event type and version
- Consumers fetch the schema at startup (and cache it)
- Schema changes are **backward-compatible** by default (add optional fields only)
- Breaking changes require a new `schema_version` and a migration window

Without schema registry, one team adds a field, another team's consumer crashes. Don't skip this.

## Partitioning — for ordering

Kafka guarantees order **within a partition**, not across partitions. Choose the partition key carefully:

- `jobs.applications` partitioned by `job_id` — all events for one job stay in order
- `identity.users` partitioned by `user_id` — all events for one user stay in order
- `payments.subscriptions` partitioned by `subscription_id`

If you partition randomly, two events for the same job could be processed in reverse order. Bad.

## The outbox pattern — atomic write + emit

The classic two-write problem: a service updates its DB **and** publishes an event. If the DB write succeeds but the Kafka publish fails (or vice versa), state diverges.

Solution: write the event to an `outbox` table inside the same DB transaction.

```
BEGIN;
INSERT INTO applications (...);
INSERT INTO outbox (event_type, payload, ...);
COMMIT;
```

A separate worker process (the "outbox publisher") tails the outbox table and publishes rows to Kafka. Once published successfully, it marks the row as sent.

This guarantees: **if the DB transaction committed, the event will eventually be in Kafka.**

Every producing service has its own outbox table.

## Consumer groups & idempotency

Each service gets its own consumer group (a label Kafka uses to track read progress).

| Service | Consumer group |
|---|---|
| Notification Service | `notification-service` |
| Resume Parser | `resume-parser` |
| Search Service | `search-service` |
| Reporting Service | `reporting-service` |

Within a consumer group, Kafka load-balances partitions across instances. Five Notification pods → Kafka splits the partitions among them.

**Idempotency is mandatory** — Kafka delivers "at-least-once" by default. A consumer may see the same event twice. So consumers must:

- Use the `event_id` as a deduplication key
- Store seen `event_id`s in Redis (TTL ~24h) or a "processed_events" table
- Make actions idempotent (e.g., "set status to Y" not "increment counter")

## Replay — the killer feature

Imagine the Notification Service had a bug last Tuesday — it sent the wrong email template for `ApplicationCreated`. Fix the bug, then **rewind the consumer offset to last Tuesday** and let it re-process from there. Other services are unaffected.

This is impossible with a "fire HTTP call" architecture. With Kafka it's a single command.

Topics retain events for a configured period (e.g., 30 days). Important topics (audit-relevant) keep them forever.

## Dead-letter topics

When a consumer fails to process an event after N retries (e.g., schema mismatch, downstream API permanently down), it moves the event to a dead-letter topic (`<topic>.dlq`). On-call inspects the DLQ; once fixed, events can be re-injected.

## Backpressure

If a consumer is too slow, the partition lag grows. Monitor:

- **Consumer lag** (time/events behind the producer) — alert if >1 minute for hot topics
- **Throughput** (events/sec produced vs consumed)
- **Error rate** per consumer group

Grafana dashboard with these from day 1.

## Local development

Local docker-compose runs:

- **Kafka** — single broker, KRaft mode (no ZooKeeper)
- **Schema Registry** — Karapace (open-source, simpler than Confluent's)
- **Kafka UI** — Provectus' Kafka UI (browse topics, consumer groups, lag visually)

A developer testing a new event sees it appear in the UI in seconds.

## Production deployment

- Managed Kafka via **Confluent Cloud**, **AWS MSK**, or **Aiven** — running Kafka on K8s yourself is operationally heavy
- Three brokers minimum, multi-AZ
- Replication factor 3, min in-sync replicas 2
- Rolling broker upgrades — clients don't notice

## Anti-patterns to avoid

- **Using Kafka as a database** — it's a log, not a query engine. Read events, project into your DB, query the DB.
- **Huge events with full object payloads** — events should be small (id + delta). If consumers need full state, they call the producer's API.
- **Synchronous "ack" through Kafka** — don't await consumer responses; use HTTP for synchronous answers.
- **One topic for everything** — separate topics by domain so consumers only get what they care about.
- **Forgetting the outbox** — without it, events get lost on partial failures.

## Failure modes

| Failure | What happens |
|---|---|
| Kafka down | Producers' outboxes accumulate; consumers idle. When Kafka recovers, outbox publishers drain — no data loss. |
| One broker dies | Other brokers handle traffic; Kafka rebalances partitions. |
| Schema registry down | Cached schemas continue to work; new schema registrations queued. |
| Consumer too slow | Lag grows; alert fires; scale consumer or fix the bottleneck. |
| Bad event poisons the consumer | After retries, event moves to DLQ; consumer continues with the next event. |

## Where to read next

- File `07` (job-application-flow) — concrete example of an event-driven flow with outbox
- File `09` (notifications) — example consumer
- File `10` (resume-parsing) — example consumer in Python
- File `16` (observability) — tracing across event hops
