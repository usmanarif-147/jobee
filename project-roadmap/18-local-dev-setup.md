# 18 — Local Development Setup

The goal: a fresh laptop should run the entire 10-service stack with **one command**: `docker compose up -d`.

## What runs locally

| Component | Purpose | Port |
|---|---|---|
| Identity Service | Laravel | (internal) |
| Companies Service | Laravel | (internal) |
| Jobs Service | Laravel | (internal) |
| Payment Service | Laravel + Cashier | (internal) |
| Notification Service | Laravel + Horizon | (internal) |
| Chat Service | Laravel Reverb | 8080 (WebSocket) |
| Media Service | Laravel | (internal) |
| Resume Parser Service | Python + FastAPI | (internal) |
| Search Service | Laravel | (internal) |
| Reporting Service | Laravel scheduler | (internal) |
| Kong | API gateway | 8000 (proxy), 8001 (admin) |
| Postgres | one container, one DB per service | 5432 |
| Redis | cache + sessions + Reverb pub/sub | 6379 |
| Kafka | event bus (single broker, KRaft mode) | 9092 |
| Karapace | schema registry | 8081 |
| Kafka UI | browse topics, lag, schemas | 8082 |
| Meilisearch | search engine | 7700 |
| MinIO | S3-compatible storage | 9002 (API), 9003 (console) |
| ClamAV | virus scanner sidecar | 3310 |
| Mailhog | fake SMTP | 1025 (SMTP), 8025 (UI) |
| Grafana | observability UI | 3001 |
| Prometheus | metrics | 9090 |
| Loki | logs | 3100 |
| Tempo | traces | 3200 |
| Redis Commander | inspect Redis | 8083 |
| pgAdmin | inspect Postgres | 8084 |

The frontend apps (Nuxt, Vue) run on the host with `npm run dev` rather than in Docker — faster HMR.

## Three frontend apps

| App | Port | URL (with `/etc/hosts` entry) |
|---|---|---|
| Public | 3000 | `http://job-hunter.local` |
| Company | 3001 | `http://company.job-hunter.local` |
| Admin | 3002 | `http://admin.job-hunter.local` |

`/etc/hosts`:

```
127.0.0.1 job-hunter.local company.job-hunter.local admin.job-hunter.local api.job-hunter.local wss.job-hunter.local
```

## Why Kafka runs locally too

Kafka is the spine of the system. Skipping it locally means devs build features that work in dev but break in production because event flows weren't tested.

A single-broker Kafka in KRaft mode (no ZooKeeper) is fine for dev. Karapace provides the schema registry.

## Why MinIO instead of real S3

S3-compatible API. Devs use the same SDK locally and in production. Switch by changing env vars only.

## Why Mailhog

Captures all outgoing emails in a local UI. No accidental real-user emails from dev.

## Why ClamAV

So we test the virus-scanning path. ClamAV's image is heavy (~1GB, downloads signatures); devs can stop it when not actively working on file features.

## Why a full Grafana / Loki / Prometheus / Tempo stack

So devs build with observability in mind from day 1. Same dashboards as production. Catches missing instrumentation early.

## Environment configuration

Each service has a `.env` (NOT committed). The `.env.example` (committed) lists all keys with safe defaults for local. The container's entrypoint auto-creates `.env` from the example on first start.

## Hot reload

- **Laravel services:** code is bind-mounted; changes are live
- **Python parser:** uvicorn `--reload` picks up file changes
- **Frontends:** Vite HMR

Save → see change in <1 second.

## Database state

- Each service's Postgres database is in a named volume — survives restarts
- Migrations run on startup
- Seeders create realistic test data: 50 companies, 200 jobs, 1000 applicants, sample plans, sample broadcasts

A `make reset` command wipes and reseeds everything across all services.

## Useful Make commands

```
make up           # docker compose up -d (everything)
make down         # docker compose down
make logs         # tail logs from all services
make logs s=jobs  # tail logs from one service
make test         # run all tests across services
make migrate      # run migrations across services
make seed         # seed all services
make reset        # fresh migrate + seed for all services
make shell s=jobs # bash into Jobs Service container
make kafka-ui     # open Kafka UI in browser
make grafana      # open Grafana
```

## Local Kong setup

Kong runs in **DB-less declarative mode**. Config is `kong.yml` committed in the `infra` repo. Mirrors production routes.

Changes to `kong.yml` reload Kong (`make kong-reload`).

## Stripe local testing

Stripe webhooks can't reach `localhost`. Use the Stripe CLI:

```
stripe listen --forward-to localhost:8000/v1/billing/webhooks/stripe
```

The CLI prints a webhook signing secret; put it in `.env` of the Payment Service.

## Resource usage

The full stack uses ~6GB RAM (10 services + Kafka + Postgres + observability stack).

For 8GB laptops: stop services you're not actively touching (`docker compose stop reporting-service search-service` etc.).

For heavy local development: use a Hetzner cheap VPS with VS Code Remote SSH, or GitHub Codespaces.

## Common local-dev pitfalls

| Symptom | Likely cause |
|---|---|
| Service won't start with DB error | Postgres not yet healthy — entrypoint retry loop covers this |
| Kafka consumer never gets events | Topic doesn't exist — Kafka auto-create may be off; create manually via Kafka UI |
| Schema validation fails | New event schema not registered with Karapace |
| File uploads work but downloads 403 | MinIO bucket policy not set — check seeder |
| Frontend can't reach API | Missing `/etc/hosts` entries; or Kong route missing |
| Stripe webhooks don't arrive | Stripe CLI not running |
