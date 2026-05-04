# 05 — Databases

## The rule: one database per service

Every microservice owns its own database. **No service ever reads or writes another service's database.** Cross-service data flows through Kafka events or HTTP API calls — never through direct DB access.

This is the single most important architectural constraint, and the easiest to violate. Enforce it in production by giving each service its own DB credentials with no access to other databases.

## Database map

| Service | DB | Cluster (production) |
|---|---|---|
| Identity | PostgreSQL | identity-db |
| Companies | PostgreSQL | companies-db |
| Jobs | PostgreSQL | jobs-db |
| Payment | PostgreSQL | payment-db |
| Notification | PostgreSQL | notification-db |
| Chat | PostgreSQL | chat-db |
| Media | PostgreSQL | media-db |
| Resume Parser | PostgreSQL | parser-db |
| Search | (none — uses Meilisearch) | — |
| Reporting | PostgreSQL | reporting-db |

In **production**, each service connects to its own dedicated Postgres cluster (RDS instance per service). In **local dev**, a single Postgres container with a separate database per service is acceptable for resource economy — but credentials still differ per service, and Laravel's `DB_DATABASE` is set per service.

## Why one DB per service

- **Independent scaling** — Jobs DB needs read replicas before the others; only Jobs DB gets them.
- **Independent failure** — If Notification's DB is down, Identity keeps working.
- **Independent migrations** — Each service ships its own migrations on its own deploy cadence.
- **No accidental cross-tenant queries** — Impossible to JOIN tables across services.
- **Hard boundary against future shortcuts** — A new dev cannot query "the other service's table" because it doesn't exist in their connection.

## What each service's DB contains (high level)

### Identity-db
- `users`, `password_resets`, `email_verifications`, `mfa_secrets`
- `roles`, `permissions`, `role_user`, `permission_role` (Spatie schema)
- `personal_access_tokens` (Sanctum)
- `outbox` (events to publish)

### Companies-db
- `companies`, `company_users`, `company_profiles`, `company_invitations`
- `outbox`

### Jobs-db
- `jobs`, `applications`, `favourites`
- `skills`, `job_skills` (canonical skill list local to Jobs)
- `job_view_counters`, `job_click_counters` (frequently-flushed)
- `outbox`

### Payment-db
- `subscription_plans`, `subscriptions`, `invoices`
- `webhook_events` (Stripe events with `UNIQUE` on `stripe_event_id` for idempotency)
- `outbox`

### Notification-db
- `notifications` (in-app, per user)
- `device_tokens` (FCM)
- `email_log`, `delivery_attempts`
- `broadcast_jobs` (bulk-email tracking)

### Chat-db
- `conversations`, `conversation_members`, `messages`, `read_receipts`
- `outbox`

### Media-db
- `attachments` (file metadata: owner, mime, size, scan status, S3 key)
- `outbox`

### Parser-db
- `parsed_resumes` (parsed text, extracted skills, score), `parse_attempts`

### Reporting-db
- `report_runs`, `report_artifacts` (URLs to generated files)
- Denormalized view tables built from Kafka events

## Read replicas

Reads outpace writes for several services. Configure read replicas per service:

| Service | Replicas (production minimum) | Heaviest reads |
|---|---|---|
| Jobs | 2+ replicas | public job listings |
| Companies | 1 replica | profile pages |
| Identity | 1 replica | token introspection |
| Others | start with 1 | grow as traffic dictates |

Laravel supports read/write splitting natively. Direct heavy read traffic to replicas; writes to primary only.

## Sharding plan

The first table to outgrow a single node is `applications` in Jobs. The plan:

- Shard by `company_id` (or `job_id`) — keeps a single job's activity together
- Use Vitess on top of MySQL or Citus extension on Postgres
- Don't roll your own sharding logic

Until then, vertical scaling + read replicas is enough.

## Counters that don't fit a transactional DB

`job_views` and `job_clicks` are write-heavy and don't need ACID. They live in **Redis** as `INCR` counters and are flushed to Postgres every minute by a scheduled job. This avoids hammering Postgres with one-row updates.

## Connection pooling

With 50+ Jobs Service pods × 10 connections each = 500 connections — beyond Postgres' comfort zone (~200). Solution: **PgBouncer** in front of Postgres in transaction-pooling mode. Each service has its own PgBouncer instance.

## Migrations

- Each service runs its own migrations on its own deploy.
- A service's CI pipeline runs migrations against a test DB before deploying.
- Migrations must be **backwards-compatible**: ship the additive change, then ship the code that uses it. Never rename or drop in a single deploy.
- Run migrations via a Kubernetes Job that completes before the new pods roll out — never `php artisan migrate` from each pod (race condition).

## Backups

- Daily logical dumps (`pg_dump`) per service to S3
- Continuous WAL archiving for point-in-time recovery
- Cross-region replication of backups for DR
- **Restore tested monthly** — a backup that has never been restored is not a backup

## Data lifecycle

| Data | Lifecycle |
|---|---|
| `users`, `companies`, `jobs` | Forever |
| `applications` | Forever (recruiter compliance) |
| `job_view_counters` raw rows | Aggregated daily, kept 90 days, then archived |
| `notifications` (in-app) | 90 days |
| `messages` (chat) | Forever (legal); soft-delete on user request |
| `webhook_events` | 1 year |
| `parsed_resumes` | Same as the application |

Old rows archived to S3 Glacier via a scheduled job (Reporting Service).

## Cross-service joins are not allowed — how to satisfy "I need data from another service"

Three patterns:

1. **Call the API** — Companies Service calls Identity Service's API to resolve a user's email. Use this for low-frequency, on-demand lookups.
2. **Subscribe to events** — Search Service subscribes to `companies.companies` and maintains its own copy of company name + slug for indexing. Use this for high-frequency reads.
3. **Materialize views via Reporting Service** — for cross-service analytics, Reporting Service consumes events from many topics and builds a denormalized read model.

Pick by use case. Never reach into another service's tables.
