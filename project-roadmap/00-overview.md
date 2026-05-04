# 00 — Project Overview

## What we're building

A job-board platform like Glassdoor / Indeed / Rozee.pk. Three audiences:

| Audience | Domain | Role |
|---|---|---|
| Super admins | `admin.job-hunter.com` | Platform owners — manage companies, plans, reports, broadcasts |
| Companies | `company.job-hunter.com/{uuid}` | Buy a plan, post jobs, receive applications |
| Public / Applicants | `job-hunter.com` | Browse jobs, apply, save favourites |

## Goal

A **full-scale, production-grade system** designed to industry standards from day one. This is not an MVP plan and there is no "we'll add it later" hedging. Every architectural decision in this folder assumes:

- Multiple developers working in parallel
- Continuous integration and continuous delivery from the first commit
- Microservices with strict boundaries, communicating through a central event bus (Kafka)
- Production-grade observability, security, and operability

## Scale targets

The system is designed to be **horizontally scalable to arbitrary `N`**. Specific numeric targets for any deployment live in a per-environment config (see `infra/`); the design itself does not hardcode them.

| Variable | Meaning |
|---|---|
| `N_users` | Total registered users the deployment is sized for |
| `C_avg` | Average concurrent users |
| `C_peak` | Peak concurrent users |
| `C_critical` | Concurrency on a single hot resource (e.g., applicants racing to a slot-capped job) |

All capacity-planning sections (file 15) reference these variables, not concrete numbers. The architecture's correctness (slot-capacity, idempotency, outbox, etc.) holds for any `N`.

## Non-functional priorities (in order)

1. **Correctness under concurrency** — never overbook a slot-capped job
2. **Resilience** — one service failing doesn't take the whole system down
3. **Observability** — we know what's happening in production at all times
4. **Developer velocity** — independent CI/CD per service; teams ship without stepping on each other
5. **Operability** — every service can be debugged, traced, and rolled back independently

## What this folder contains

The full system design plan. Files are numbered in reading order. Each file is short, design-only, no code. Files cross-reference each other when concepts overlap.

## Architectural pillars (every file builds on these)

- **10 headless microservices**, each with a strict purpose and its own database
- **Kafka pub/sub** as the central event bus — services emit events; consumers subscribe to topics
- **Outbox pattern** — atomicity between database writes and event emission
- **Schema registry** — versioned event contracts validated at producer and consumer
- **API gateway (Kong)** — single entrypoint with auth, rate limit, routing
- **GitOps deployment** — cluster state mirrors what's in Git (ArgoCD)
- **Distributed tracing** mandatory from day 1 — `X-Request-ID` flows through every hop
- **Database per service** — no service touches another service's DB

## File index

| # | File | Topic |
|---|---|---|
| 01 | `01-actors-and-subdomains.md` | Three audiences and their domains |
| 02 | `02-architecture-overview.md` | The big picture |
| 03 | `03-microservices-breakdown.md` | The 10 services, what each owns, why split this way |
| 04 | `04-tech-stack.md` | Technology chosen at each layer |
| 05 | `05-databases.md` | One database per service; isolation, replicas, sharding |
| 06 | `06-api-gateway-and-auth.md` | Kong + Identity Service + cross-service auth |
| 07 | `07-job-application-flow.md` | The slot-capacity race condition (key correctness chapter) |
| 08 | `08-realtime-chat.md` | WebSocket layer (chat + general realtime push) |
| 09 | `09-notifications.md` | Async email + FCM + in-app notifications |
| 10 | `10-resume-parsing.md` | Async resume parsing + skill matching |
| 11 | `11-payments-subscriptions.md` | Stripe plans + expiry handling |
| 12 | `12-scheduled-jobs.md` | Cron, sweepers, reports |
| 13 | `13-file-storage.md` | Media Service, presigned URLs, file safety |
| 14 | `14-caching-and-search.md` | Caching strategy + Search Service in front of Meilisearch |
| 15 | `15-scaling-strategy.md` | Production-scale traffic from day 1 |
| 16 | `16-observability.md` | Logs, metrics, traces, alerts |
| 17 | `17-team-workflow.md` | Git, PRs, CI/CD per service |
| 18 | `18-local-dev-setup.md` | Running the whole stack on localhost |
| 19 | `19-production-deployment.md` | AWS EKS / DOKS, GitOps, secrets |
| 20 | `20-security.md` | Top concerns and mitigations |
| 21 | `21-rollout-phases.md` | Delivery milestones — slices of full-scale capability |
| 22 | `22-event-bus-and-pubsub.md` | The Kafka spine: topics, schemas, outbox, replay |

## Recommended reading order

1. **Read 00 → 03** to understand the system shape.
2. **Read 22** next — pub/sub is the spine that ties every service together.
3. **Read 07** — it's the most important correctness chapter (slot capacity).
4. From there, jump to whichever capability you're about to build.
