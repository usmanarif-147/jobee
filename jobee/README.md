# Jobee

Full-scale microservices job board platform — admin, company, and applicant audiences served by 10 backend services and 3 frontend apps.

> **Status:** Sprint 0 — local platform infrastructure only. No services exist yet. The compose stack stands up Postgres, Redis, Kafka, Kong, MinIO, Mailhog, ClamAV, Meilisearch, and the Grafana/Prometheus/Loki/Tempo observability stack.

## Repo layout

```
jobee/
├── services/         # 10 backend microservices (empty until Sprint 1)
├── web/              # 3 frontend apps (empty until Sprint 3)
├── infra/            # Per-container config (kong, prometheus, tempo, grafana)
├── scripts/          # Init scripts (e.g. seed-buckets.sh for MinIO)
├── docs/             # Project-local docs (start with 00-getting-started.md)
├── docker-compose.yml
├── Makefile
└── .env.example
```

## Prerequisites

- Docker Engine 24+ with **Compose v2** (`docker compose`, not `docker-compose`)
- GNU Make
- ~6 GB free RAM (the full stack uses around that much when warm)
- `sudo` access for one `/etc/hosts` edit

## First-time setup

### 1. Copy the env file

```bash
cp .env.example .env
```

All defaults work for local dev. Edit only if a port conflicts with something already running on your machine.

### 2. Add the dev hostnames to `/etc/hosts`

The architecture uses 5 subdomains. They must resolve to `127.0.0.1` so Kong can route by hostname.

```bash
sudo tee -a /etc/hosts >/dev/null <<'EOF'

# START Jobee Development Hosts
127.0.0.1 job-hunter.local
127.0.0.1 company.job-hunter.local
127.0.0.1 admin.job-hunter.local
127.0.0.1 api.job-hunter.local
127.0.0.1 wss.job-hunter.local
# END Jobee Development Hosts
EOF
```

Verify:

```bash
getent hosts api.job-hunter.local   # should print 127.0.0.1
```

### 3. Bring the stack up

```bash
make up
```

First boot pulls a few GB of images and downloads ClamAV virus signatures — give it 2–3 minutes.

## Verify

```bash
make ps
```

Every container should be `healthy` or `running`. Then open the dashboards:

| URL | What you'll see | Default credentials |
|---|---|---|
| http://localhost:8000 | Kong proxy — 404 (no routes yet, expected) | — |
| http://localhost:8001 | Kong admin API JSON | — |
| http://localhost:8082 | Kafka UI — empty cluster | — |
| http://localhost:8081 | Karapace schema registry | — |
| http://localhost:8025 | Mailhog inbox | — |
| http://localhost:9003 | MinIO console | `jobee` / `jobee_local_password` |
| http://localhost:7700/health | Meilisearch health JSON | — |
| http://localhost:3001 | Grafana | `admin` / `jobee_local_password` |
| http://localhost:9090 | Prometheus | — |
| http://localhost:8084 | pgAdmin | `admin@jobee.local` / `jobee_local_password` |
| http://localhost:8083 | Redis Commander | — |

## Common commands

```bash
make help            # list every available make target
make up              # start everything
make down            # stop (volumes preserved)
make restart         # restart all services
make ps              # show service status
make logs            # tail all logs
make logs s=kafka    # tail one service's logs
make reset           # stop AND DELETE volumes (fresh slate)
make shell-postgres  # psql into Postgres
make shell-redis     # redis-cli into Redis
make seed-buckets    # re-create MinIO buckets if needed
```

## Architecture at a glance

- **10 backend microservices** (Identity, Companies, Jobs, Payment, Notification, Chat, Media, Resume Parser, Search, Reporting) each with its own logical database and migrations.
- **3 frontend apps** (public Nuxt site, company Vue panel, admin Vue panel).
- **Kong API gateway** is the single inbound door — clients hit `api.job-hunter.local:8000` and Kong routes to the correct service.
- **Kafka** is the async spine — services emit domain events; consumers subscribe.
- **Outbox pattern** + **schema registry** (Karapace) make event delivery reliable and contract-safe.

## Read more

- `docs/00-getting-started.md` — full Sprint 0 walkthrough, request-flow diagram, and sprint roadmap.
- `../project-roadmap/` — 22-file system design (start with `00-overview.md`).
- `../project-structure/01-folder-tree.md` — full monorepo layout reference.

## What's next

Sprint 1 — scaffold the **Identity Service** (Laravel) under `services/identity-service/`, add it to `docker-compose.yml`, and register the first Kong route in `infra/kong/kong.yml`.
