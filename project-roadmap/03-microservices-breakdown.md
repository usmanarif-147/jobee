# 03 — Microservices Breakdown

## The 10 headless microservices

Each is **HTTP API only** (no UI). Each owns its own database. None reads another's database. Communication across services is via Kafka topics for async or HTTP through Kong for sync.

| # | Service | Tech | DB? | What it owns |
|---|---|---|---|---|
| 1 | **Identity Service** | Laravel | ✅ | users, roles, permissions, sessions, tokens, MFA |
| 2 | **Companies Service** | Laravel | ✅ | companies, company_users, company profiles |
| 3 | **Jobs Service** | Laravel | ✅ | jobs, applications, favourites, skills, view counters |
| 4 | **Payment Service** | Laravel + Cashier | ✅ | plans, subscriptions, invoices, webhook events |
| 5 | **Notification Service** | Laravel + Horizon | ✅ | email log, FCM tokens, in-app notifications |
| 6 | **Chat Service** | Laravel Reverb | ✅ | conversations, messages, WebSocket connections, realtime push |
| 7 | **Media Service** | Laravel | ✅ | file metadata, presigned URLs, virus scan coordination |
| 8 | **Resume Parser Service** | Python + FastAPI | ✅ | parsed text, extracted skills, match scores |
| 9 | **Search Service** | Laravel (thin wrapper) | ❌ (Meilisearch is the store) | tenancy filters, ranking config |
| 10 | **Reporting Service** | Laravel scheduler | ✅ | scheduled report runs, exported file references |

## What each service does (one paragraph each)

### 1. Identity Service
The single source of truth for "who is the user and what can they do?" Handles signup, email verification, login, MFA, roles, permissions, and token issuance. Issues short-lived JWTs for cross-service auth and Sanctum cookies for SPA sessions. Other services call its `/introspect` endpoint to validate tokens (cached for a few seconds in Kong). Emits `UserRegistered`, `UserEmailVerified`, `UserDeleted` events.

### 2. Companies Service
Owns companies, company-staff relationships, and company profiles. Handles "this user belongs to this company with this role inside it." Subscription gates are enforced here too (resolve "is this company subscribed?" using a cached read from Payment Service's events). Emits `CompanyRegistered`, `CompanyUserAdded`, etc.

### 3. Jobs Service
The core domain service. Owns job posts AND applications AND favourites AND view counters. Keeping jobs and applications in one DB is intentional — the slot-capacity correctness check (see file 07) requires a single transaction. Emits `JobCreated`, `JobClosed`, `ApplicationCreated`, `ApplicationStatusChanged`.

### 4. Payment Service
All Stripe interactions. Plans, subscriptions, invoices, Stripe webhooks. Receives Stripe webhook calls directly (Kong route bypasses normal auth — uses Stripe signature instead). Emits `SubscriptionActivated`, `PaymentFailed`, `SubscriptionExpired`. Companies Service subscribes to these to update its subscription cache.

### 5. Notification Service
**Async only.** Consumes events from many topics, decides who should be notified, dispatches via:
- Email (Postmark for transactional, SES for bulk)
- FCM push for mobile
- In-app DB row (companies/admins read these via the API)

Has no WebSocket connections (those live in Chat Service). Pure queue worker design.

### 6. Chat Service
Owns chat data and **all WebSocket connections**. Two responsibilities:
1. Chat — conversations, messages, file attachments, presence
2. General realtime push — when an in-app notification is created, Chat Service pushes a "you have a new notification" event to that user's WebSocket so the bell icon updates instantly

Subscribes to topics like `notifications.in_app_created` to support #2.

### 7. Media Service
The gatekeeper for object storage. Issues presigned upload URLs (after auth check), tracks file metadata (`attachments` table), coordinates ClamAV virus scanning, issues presigned download URLs. Other services don't talk to S3 directly — they go through Media Service.

Emits `FileUploaded`, `FileScanClean`, `FileScanInfected`, `FileDeleted`. Resume Parser, for example, listens for `FileScanClean` on resume uploads.

### 8. Resume Parser Service
Python + FastAPI. Consumes `jobs.applications` (specifically `ApplicationCreated` events). Fetches the resume via Media Service. Extracts text and skills using Python ML libraries. Computes a match score against the job's required skills. Emits `ResumeParsed` so Jobs Service (or anyone) can update the application with parse results.

### 9. Search Service
Thin wrapper in front of Meilisearch. The frontend never hits Meilisearch directly because:
- The Meilisearch API key would leak
- Tenancy filters (admin sees more, public sees less) need server enforcement
- Custom ranking might evolve

Subscribes to `jobs.jobs`, `jobs.applications` to keep the Meilisearch index live. Exposes a clean public API: `GET /search/jobs?q=...&filters=...`.

### 10. Reporting Service
Generates scheduled platform reports (daily / weekly / monthly). Subscribes to many event topics to build a denormalized "reports" view. Generates PDFs and CSVs, uploads via Media Service, emails the result to admins.

## Why these specific splits

| Split decision | Reason |
|---|---|
| Identity owns roles + permissions | Splitting auth from authz adds a hop on every request — too costly |
| Companies separate from Identity | Companies and users are different domains; companies can have many users with company-scoped roles |
| Jobs + Applications together | Slot-capacity correctness needs one DB transaction across both tables |
| Payment is its own service | Webhook ordering, idempotency, and audit needs strict isolation |
| Notification has no WebSocket | Different runtime model — async workers vs long-lived connections |
| WebSocket lives in Chat | Chat already needs WebSocket; one service handles all realtime push |
| Search wraps Meilisearch | Auth, tenancy, ranking customization belong in our code, not at the search engine |
| Media owns S3 access | Centralized auth, virus scanning, audit logging on file access |
| Resume Parser is Python | PDF/DOCX/NLP libraries are best in Python |
| Reporting is its own service | Heavy CPU and IO patterns; runs on its own pool |

## The headless rule

No microservice has its own UI. Frontends (admin, company, public) are separate apps that talk to the API gateway. This means:

- Frontends can be redeployed without touching backend
- Backend can be exposed to mobile / third-party clients with no extra work
- API contracts are explicit (OpenAPI specs published)

## Communication summary

```
Sync (request-response):
  Frontend → Kong → Identity (introspect) → cached → forwarded to target service

Async (events):
  Service A → outbox table → outbox publisher → Kafka topic → Service B / C / D consumers

Realtime to clients:
  Backend service → Kafka topic OR direct internal call → Chat Service → WebSocket → client
```

## Service templates

For consistency, each Laravel service is scaffolded from the same template:

- Same Dockerfile structure
- Same health endpoints (`/health/live`, `/health/ready`)
- Same `/metrics` Prometheus endpoint
- Same OpenTelemetry instrumentation
- Same logging format (structured JSON to stdout)
- Same outbox pattern implementation
- Same Kafka client wrapper

A new service in this organization should be runnable in production within a day of being scaffolded.

## Where Rust fits (your interest)

Resume Parser stays Python — Python's NLP ecosystem is unmatched. The natural future home for Rust in this system is a **counter / rate-limiter sidecar** or a **fan-out service** for very high-throughput WebSocket broadcasting (if Reverb hits limits). Until then, don't bring in a new language without a real reason.
