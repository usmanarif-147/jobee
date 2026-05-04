# 02 — Architecture Overview

## The big picture

```
            Browsers / Mobile apps
            (3 frontend apps)
                     │
                     ▼
             Cloudflare (CDN + DDoS + DNS + SSL)
                     │
                     ▼
             Kong API Gateway (auth, routing, rate limit)
                     │
   ┌─────────┬───────┼─────────┬──────────┬─────────┬──────────┬──────────┬──────────┐
   ▼         ▼       ▼         ▼          ▼         ▼          ▼          ▼          ▼
Identity  Companies Jobs    Payment   Notification Chat     Media     Resume     Search
Service   Service   Service Service   Service     Service  Service   Parser     Service
                                                                     Service    (wraps
                                                                                Meilisearch)
   │         │      │          │          │         │         │         │
   └────┬────┴──────┴────┬─────┴──────────┴─────────┴─────────┴─────────┘
        │                │
        ▼                ▼
   Postgres          Kafka                  ←  the event bus (pub/sub spine)
   (one DB           (topics, consumer
   per service)      groups, schema
                     registry)
        │                │
        ▼                ▼
   Redis (cache,      S3 / MinIO       Stripe / FCM / SES (external)
   sessions,         (object storage,
   Reverb pub/sub)   owned by Media)
```

Plus a Reporting Service that reads from many topics to build cross-service reports.

## The layers, explained

### 1. Edge — Cloudflare
Sits in front of everything. DNS, SSL (HTTPS), DDoS protection, WAF, CDN for static assets.

### 2. Gateway — Kong
Single entrypoint. Validates auth (calls Identity Service for token introspection, with caching), enforces rate limits, injects `X-Request-ID` for tracing, and routes by host/path to the right backend service.

### 3. Microservices — 10 headless services
All services are HTTP-only (no UI). Each owns its own slice of the domain. The detailed list is in `03-microservices-breakdown.md`.

### 4. Event bus — Kafka
The central place for cross-service communication. Producers publish events; consumers subscribe to topics. Replayable, ordered per partition, durable. The full design is in `22-event-bus-and-pubsub.md`.

### 5. Data layer
- **Postgres** — one cluster per service in production. No shared schemas across services.
- **Redis** — cache, sessions, rate-limit counters, Reverb pub/sub fan-out.
- **S3 / MinIO** — object storage; access mediated by Media Service.
- **Meilisearch** — backing search engine; fronted by Search Service.

## Communication rules

| Pattern | When to use | Mechanism |
|---|---|---|
| Synchronous read | "I need this answer right now" (e.g., resolve a user from a token) | HTTP via Kong |
| Asynchronous reaction | "X happened — anyone who cares should react" | Kafka event |
| Realtime push to clients | New chat message, live notification badge | WebSocket via Chat Service |
| Mobile push | New application notification | FCM via Notification Service |

**No service writes to another service's database, ever.** If service A needs data owned by service B, it either calls B's API or subscribes to B's topic.

## How a typical action flows (apply to a job)

1. Browser → Kong → Jobs Service (`POST /jobs/{id}/apply`)
2. Jobs Service: validate, lock slot in DB, insert application + write outbox row (one transaction)
3. Outbox publisher tails the outbox table → publishes `ApplicationCreated` to Kafka topic `jobs.applications`
4. **Notification Service** consumes → fans out FCM + email
5. **Resume Parser** consumes → fetches resume via Media Service → parses → publishes `ResumeParsed`
6. **Search Service** consumes → updates the application count in Meilisearch
7. **Chat Service** (subscribed too) → pushes a live notification badge to the company's WebSocket-connected users

The applicant gets a 200 response in milliseconds — everything else happens asynchronously.

## What lives where (rule of thumb)

- **State that must be ACID** → SQL DB owned by one service
- **Throwaway hot data** (sessions, cache, counters) → Redis
- **Cross-service events** → Kafka topics
- **Big binary blobs** (resumes, chat files, reports) → S3 (Media Service controls access)

## Why this design from day 1

- **No technical debt from a future "split the monolith" project** — boundaries are clear up front.
- **Independent scaling** — each service scales by its own load profile.
- **Independent deploy** — each service has its own pipeline.
- **Independent failure** — one service down does not cascade.
- **Replayability** — events stored in Kafka let consumers re-process the past.

## What this design demands

- **CI/CD per service** — automated test, build, deploy on every merge
- **Distributed tracing** — without it, debugging is impossible
- **Schema registry** for events — without it, breaking changes leak
- **Outbox pattern** — without it, events are lost on partial failures

These are mandatory infrastructure. Not "nice to have."
