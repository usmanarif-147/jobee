# 04 — Tech Stack

The single source of truth for **what we use** at each layer. Decisions are final — this is a full-scale system designed for production from day 1.

## Frontend (3 separate apps)

| App | Tech | Why |
|---|---|---|
| Public site (`job-hunter.com`) | Nuxt 3 (Vue) | SEO matters for job listings; SSR is mandatory |
| Company panel (`company.job-hunter.com`) | Vue 3 SPA | Authenticated, SEO doesn't matter, SPA is enough |
| Admin panel (`admin.job-hunter.com`) | Vue 3 SPA | Same reasoning as company panel |

One framework family across all three — consistent skills, shared component library.

## Backend (10 microservices)

| Service | Tech |
|---|---|
| Identity | Laravel + Sanctum |
| Companies | Laravel |
| Jobs | Laravel |
| Payment | Laravel + Cashier (Stripe) |
| Notification | Laravel + Horizon |
| Chat | Laravel Reverb |
| Media | Laravel |
| Resume Parser | Python + FastAPI |
| Search | Laravel (thin wrapper over Meilisearch) |
| Reporting | Laravel scheduler |

## Data layer

| Component | Choice | Notes |
|---|---|---|
| Primary DB | PostgreSQL 16 | Advisory locks, `SELECT FOR UPDATE`, JSON, full-text — fits all services |
| Per-service isolation | One Postgres cluster per service in production | No shared schemas across services |
| Cache + sessions + rate limit | Redis 7 | Same Redis cluster shared across services with separate key namespaces |
| Reverb pub/sub fan-out | Redis 7 | Reverb uses Redis to broadcast across instances |
| Event bus | **Apache Kafka** | The central pub/sub spine — see file 22 |
| Schema registry | Karapace (open-source) or Confluent Schema Registry | Versioned event contracts |
| Object storage | AWS S3 (prod) / MinIO (dev) | Owned by Media Service |
| Search engine | Meilisearch | Wrapped by Search Service |

## Infrastructure

| Component | Choice |
|---|---|
| Container runtime | Docker |
| Local orchestration | Docker Compose (the entire stack runs locally) |
| Production orchestration | Kubernetes (managed: AWS EKS or DigitalOcean DOKS) |
| API gateway | Kong |
| Reverse proxy in front of services | Nginx (built into Laravel containers) |
| CDN + DNS + SSL | Cloudflare |
| Cloud provider | AWS (EKS, RDS, ElastiCache, S3, MSK, SES, Secrets Manager) |
| Image registry | GitHub Container Registry (GHCR) |
| Deployment | ArgoCD (GitOps — cluster mirrors what's in Git) |

## Observability — mandatory from day 1

| Concern | Choice |
|---|---|
| Errors | Sentry (one project per service) |
| Logs | Grafana Loki (structured JSON shipped via Vector or Promtail) |
| Metrics | Prometheus + Grafana |
| Distributed traces | OpenTelemetry → Tempo (Grafana) or Jaeger |
| Uptime | UptimeRobot |
| Alerts | Prometheus Alertmanager → Slack / PagerDuty |

## CI/CD & team workflow

| Concern | Choice |
|---|---|
| Version control | GitHub (single monorepo with per-service folders under `services/`, `web/`, `infra/`, `event-schemas/`, `docs/`) |
| Pull request reviews | Required, GitHub branch protection |
| CI | GitHub Actions (one pipeline per service) |
| CD | GitHub Actions builds Docker image → ArgoCD deploys |
| Issue tracking | GitHub Issues + Projects |
| Container registry | GHCR |
| Docs | Markdown in each service folder + this `project-roadmap/` folder |

## Auth & security

| Concern | Choice |
|---|---|
| Identity store | Identity Service (Laravel + Sanctum) |
| Cross-service tokens | Short-lived JWTs issued by Identity Service |
| Frontend session | Sanctum cookie scoped to subdomain |
| RBAC library | spatie/laravel-permission inside Identity Service |
| Secrets | AWS Secrets Manager (prod), `.env` (local) |
| WAF + DDoS | Cloudflare |

## External services

- **Stripe** — subscriptions, webhooks (Payment Service)
- **Firebase Cloud Messaging (FCM)** — mobile push (Notification Service)
- **Postmark** — high-deliverability transactional email
- **AWS SES** — bulk / broadcast email
- **ClamAV** — virus scanning sidecar (Media Service)

## Why Kafka and not alternatives

- Multiple consumer groups — different services consume the same topic at their own pace
- Replayability — historical events can be re-processed after bug fixes
- Horizontal scaling — partitions distribute load
- Industry standard — large ecosystem, mature managed offerings (AWS MSK, Confluent Cloud, Aiven)

Single broker for local dev (KRaft mode, no ZooKeeper). Three-broker cluster minimum in production.

## Things that are explicitly inside the stack from day 1

- Kafka (no "skip locally" option)
- Schema registry (every event has a versioned contract)
- OpenTelemetry instrumentation (no service ships without traces)
- ArgoCD GitOps (no manual `kubectl apply`)
- Outbox pattern (every producer service has an outbox table)
- Per-service CI pipelines (no merge without green checks)

If any of these is missing, the system isn't running to spec.

## Cost note

Running a 10-service Kafka-based system on AWS EKS is meaningful infrastructure. Practising it locally with Docker Compose is free; a representative production deploy starts from a few hundred USD/month. Discussions of cost are out of scope for these design files.
