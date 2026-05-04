# 00 — Getting Started

Concrete starting point for building this monorepo. Read this before writing any service code.

## Direct answers

| Question | Answer |
|---|---|
| One Dockerfile, or one per service? | **One per service** at `services/<svc>/Dockerfile`. That's the production image. |
| One root `docker-compose.yml`, or many? | **One at the root**. It references each service's Dockerfile via `build: ./services/<svc>`. |
| Start with a specific service or with system wiring? | **Neither — start with empty infra.** Get Kafka + Postgres + Redis + Kong + observability up first, with zero services. |
| Which service first after that? | **Identity Service.** Same logic as a monolith ("auth first"). Kong introspects against it for every other request, so nothing else can authenticate without it. |
| How does this fit agile? | Each sprint produces one demoable vertical slice. Milestones in `project-roadmap/21-rollout-phases.md` are already shaped that way. |

## How a request flows

```
Browser
  → Cloudflare (DNS, SSL, WAF)
  → Kong API gateway (api.job-hunter.com)
      ├── reads hostname + path
      ├── extracts auth token from cookie / header
      ├── checks Redis cache for token; on miss calls Identity /introspect
      ├── injects X-Request-ID, X-User-ID, X-User-Roles
      └── routes by path:
            /v1/auth/*       → Identity
            /v1/companies/*  → Companies
            /v1/jobs/*       → Jobs
            /v1/billing/*    → Payment
            /v1/media/*      → Media
            /v1/search/*     → Search
            ...
  → target service (trusts Kong's headers — Kong is the only inbound path)
  → service does its work (DB read/write + optional outbox row in same transaction)
  → response back through Kong to browser
```

Async side effects (FCM pushes, emails, resume parse, search index updates, realtime push to bell icon) happen via Kafka events emitted from the outbox table — the user's HTTP response doesn't wait for them.

## Why infra comes before any service

In a monolith you start with auth because "everything connects to user." In a microservice system you start **one level deeper** — with the platform itself — because Identity Service can't run without Postgres + Kafka + Kong already standing. The infra is the analog of `composer install` in the monolith world: it's the prerequisite to everything else.

## Sprint plan (agile vertical slices)

Each sprint produces something demoable in a browser or terminal.

### Sprint 0 — Empty platform comes up (Milestone 0)

Goal: `make up` brings up all infra, no business logic yet.

Files to create at the root of `jobee/`:

- `docker-compose.yml` — wires up Postgres, Redis, Kafka (KRaft, single broker), Karapace (schema registry), Kafka UI, Kong (DB-less declarative), MinIO, Mailhog, ClamAV, Grafana, Loki, Prometheus, Tempo, Meilisearch, pgAdmin, Redis Commander.
- `Makefile` — `make up`, `make down`, `make logs`, `make logs s=<svc>`, `make reset`.
- `.env.example` — shared env vars (DB password, Kafka bootstrap, MinIO keys).
- `infra/kong/kong.yml` — declarative Kong config; initially zero routes (just the gateway running).
- `infra/docker-compose/` — supplementary compose fragments if needed (observability stack split out for clarity).
- `scripts/seed-buckets.sh` — creates MinIO buckets (`resumes`, `chat-files`, `reports`, `company-assets`, `avatars`).
- `README.md` — quickstart: prereqs, `/etc/hosts` entries, `make up`, dashboard links.

`/etc/hosts` (one-time, on the dev machine):

```
127.0.0.1 job-hunter.local company.job-hunter.local admin.job-hunter.local api.job-hunter.local wss.job-hunter.local
```

**Demo:** `make up` → all containers healthy → Grafana, Kafka UI, Mailhog, MinIO console, pgAdmin all open in the browser. No services yet, but the platform is live.

### Sprint 1 — Service template + first hello-world service

Goal: prove a Laravel service can run inside the platform end-to-end.

- `services/identity-service/Dockerfile` (PHP 8.3 + nginx + Laravel)
- Skeleton Laravel app with:
  - `/health/live` and `/health/ready`
  - `/metrics` (Prometheus exporter)
  - OpenTelemetry init (traces shipped to Tempo)
  - Structured JSON logging to stdout
  - `outbox` table migration + a stub outbox publisher worker
  - Kafka client wrapper (php-rdkafka or rdkafka over Composer)
- Add the service to root `docker-compose.yml`.
- Add a Kong route in `infra/kong/kong.yml`: `/v1/auth/health` → identity-service.
- Once this works, copy this scaffold for every future Laravel service.

**Demo:** `curl http://api.job-hunter.local:8000/v1/auth/health/live` → 200 OK; the request shows up as a trace in Grafana Tempo with the Kong → Identity hop.

### Sprint 2 — Identity Service: signup + login (Milestone 1, slice 1)

Goal: real users can be created and authenticated.

- Migrations: `users`, `password_resets`, `email_verifications`, `personal_access_tokens`, Spatie roles/permissions.
- Endpoints: `POST /v1/auth/signup`, `POST /v1/auth/login`, `POST /v1/auth/verify-email`, `POST /v1/auth/introspect`.
- Email verification dispatched via queued job → SMTP → Mailhog.
- Emit `UserRegistered`, `UserEmailVerified` events via outbox → Kafka topic `identity.users`.
- Kong auth plugin configured to call `/introspect` and cache in Redis.
- Three guards (`admin`, `company`, `web`) wired up.

**Demo:** `curl` signup → email visible in Mailhog → `curl` verify → `curl` login returns a token → `curl /v1/auth/introspect` echoes the user → events visible in Kafka UI.

### Sprint 3 — First frontend (public-web) hooks to Identity (Milestone 1, slice 2)

Goal: a real browser flow.

- `web/public-web/` — Nuxt 3 scaffold with login + signup pages.
- `/etc/hosts` already maps `job-hunter.local` to the dev server.
- Frontend calls `api.job-hunter.local:8000/v1/auth/*` through Kong.

**Demo:** open `http://job-hunter.local:3000`, sign up in the browser, log in, see the user resolved.

### After Sprint 3 — Repeat the pattern

You now have a proven loop: `Frontend → Kong → Service → DB → Kafka → Consumers`. Every later feature (Companies → Jobs → Payment → Media → Notification → Chat → Resume Parser → Search → Reporting) follows the same cookie-cutter shape. Order = Milestones 1–9 from `project-roadmap/21-rollout-phases.md`.

## Where to look in the roadmap

| Topic | File |
|---|---|
| System shape, scale variables | `project-roadmap/00-overview.md` |
| What each service owns | `project-roadmap/03-microservices-breakdown.md` |
| Kong + Identity wiring (Sprint 1–2) | `project-roadmap/06-api-gateway-and-auth.md` |
| Exact local stack contents (Sprint 0) | `project-roadmap/18-local-dev-setup.md` |
| Milestone-by-milestone delivery | `project-roadmap/21-rollout-phases.md` |
| Outbox pattern, Kafka topic naming, schema registry | `project-roadmap/22-event-bus-and-pubsub.md` |
| Folder layout (matches `jobee/`) | `project-structure/01-folder-tree.md` |

## Verification for Sprint 0

When you finish Sprint 0, all of these should work:

1. `cd jobee && make up`
2. `docker compose ps` — every container is `healthy` or `running`.
3. Browser dashboards reachable:
   - `http://localhost:8000` — Kong proxy (404 OK, no routes registered yet)
   - `http://localhost:8001` — Kong admin
   - `http://localhost:8082` — Kafka UI (shows zero topics)
   - `http://localhost:8025` — Mailhog
   - `http://localhost:9003` — MinIO console
   - `http://localhost:3001` — Grafana (empty dashboards)
   - `http://localhost:7700` — Meilisearch
4. `docker compose logs --tail=50` shows no fatal errors.

Once those pass, Sprint 0 is done — and Sprint 1 begins by adding the first service Dockerfile and one Kong route.
