# 21 — Delivery Milestones

The system is designed to be full-scale and production-grade from day 1. There is no "MVP first, scale later" plan. Instead, we deliver in **vertical slices** — each milestone is a complete, demoable, production-deployable piece of the full architecture.

The infrastructure (gateway, Kafka, observability, CI/CD) is built before any business feature, because building features on top of missing infrastructure creates rework.

## Milestone 0 — Platform foundation

Before any feature lands.

| Capability | Status |
|---|---|
| GitHub monorepo with `services/`, `web/`, `infra/`, `event-schemas/`, `docs/` folders | ✅ |
| GitHub Actions CI pipeline template (lint, test, build, scan) | ✅ |
| Docker Compose stack for local dev (all 10 services + infra) | ✅ |
| Kong API gateway with declarative config | ✅ |
| Kafka cluster (single broker for dev, 3-broker plan for prod) | ✅ |
| Karapace schema registry | ✅ |
| Postgres clusters scaffolded per service | ✅ |
| Redis cluster | ✅ |
| MinIO (dev) / S3 (prod) | ✅ |
| Loki + Prometheus + Grafana + Tempo running | ✅ |
| OpenTelemetry instrumentation in service template | ✅ |
| Outbox pattern in service template | ✅ |
| ArgoCD set up for GitOps deploys to a staging cluster | ✅ |

## Milestone 1 — Identity & Companies

| Capability | Status |
|---|---|
| Identity Service: signup, login, email verification, password reset, MFA | ✅ |
| Identity: roles + permissions (Spatie schema) | ✅ |
| Identity: introspect endpoint for Kong | ✅ |
| Identity: emits `UserRegistered`, `UserEmailVerified` events | ✅ |
| Companies Service: company registration, profile, company-users | ✅ |
| Companies: emits company events; subscribes to subscription events | ✅ |
| Three frontends scaffolded with subdomain routing + auth pages | ✅ |

After this milestone: anyone can sign up as admin, company, or applicant.

## Milestone 2 — Jobs & Applications

| Capability | Status |
|---|---|
| Jobs Service: CRUD jobs, applicant cap, deadline | ✅ |
| Jobs: slot-capacity correctness (DB row lock + unique constraint) | ✅ |
| Jobs: outbox pattern emitting `JobCreated`, `ApplicationCreated`, etc. | ✅ |
| Public job listing page with filters | ✅ |
| Apply flow with resume upload (via Media Service) | ✅ |
| Job auto-close sweeper | ✅ |

After this milestone: applicants can browse and apply; companies can post jobs.

## Milestone 3 — Payments

| Capability | Status |
|---|---|
| Payment Service with Stripe Cashier | ✅ |
| Plans created by admin, mirrored from Stripe | ✅ |
| Stripe Checkout for company subscriptions | ✅ |
| Stripe webhooks (idempotent, signed) | ✅ |
| Subscription gate on job creation (via Companies' cached status) | ✅ |
| Expiry sweeper + 7/3/1-day reminders | ✅ |

After this milestone: companies must subscribe to post jobs.

## Milestone 4 — Media & File Handling

| Capability | Status |
|---|---|
| Media Service: presigned upload + download URLs | ✅ |
| Media: tracks attachment metadata | ✅ |
| ClamAV virus scanning sidecar with event-driven flow | ✅ |
| Lifecycle policies in S3 | ✅ |
| All other services use Media Service for file ops (no direct S3) | ✅ |

After this milestone: every file passes through a centralized, scanned, audit-logged path.

## Milestone 5 — Notifications

| Capability | Status |
|---|---|
| Notification Service consuming Kafka topics | ✅ |
| Email (Postmark transactional + SES bulk) | ✅ |
| FCM push notifications | ✅ |
| In-app notifications (DB rows + REST API) | ✅ |
| Bulk email broadcast (chunked, parallel) | ✅ |
| Notification preferences per user | ✅ |

After this milestone: users get email, push, and in-app notifications.

## Milestone 6 — Resume Parsing

| Capability | Status |
|---|---|
| Resume Parser Service (Python + FastAPI) | ✅ |
| Consumes `jobs.applications` events | ✅ |
| Extracts text + skills + match score | ✅ |
| Emits `ResumeParsed` events | ✅ |
| Jobs Service updates application with parse results | ✅ |
| Skill dictionary + admin UI to manage it | ✅ |

After this milestone: applicants are auto-ranked by skill match.

## Milestone 7 — Realtime (Chat + general push)

| Capability | Status |
|---|---|
| Chat Service running Reverb in production | ✅ |
| One-to-one conversations between admin / companies | ✅ |
| Subscription gate for company-to-company chat | ✅ |
| File attachments (via Media Service) | ✅ |
| Read receipts, presence, typing | ✅ |
| Chat Service consumes `notifications.in_app_created` and pushes to bell-icon channels | ✅ |

After this milestone: users see realtime updates and can chat with file sharing.

## Milestone 8 — Search

| Capability | Status |
|---|---|
| Search Service in front of Meilisearch | ✅ |
| Indexing driven by Kafka consumers | ✅ |
| Filtered search (skills, location, salary, dates) | ✅ |
| Tenancy filtering enforced in Search Service | ✅ |
| Reindex from Kafka topic on demand | ✅ |

After this milestone: users have fast, fuzzy, filtered job search.

## Milestone 9 — Reporting & Admin

| Capability | Status |
|---|---|
| Admin dashboard with platform metrics | ✅ |
| Reporting Service generating daily / weekly / monthly reports | ✅ |
| Admin bulk actions (announcements, suspending companies) | ✅ |
| Audit log of admin actions | ✅ |
| PDF / CSV exports via Media Service | ✅ |

After this milestone: the platform is operable by a real business team.

## Milestone 10 — Production hardening + scale

| Capability | Status |
|---|---|
| Multi-AZ deployments for all stateful tiers | ✅ |
| Read replicas for high-traffic services | ✅ |
| Cross-region S3 replication for resumes | ✅ |
| WAF rules at Cloudflare | ✅ |
| Disaster recovery runbook tested in a different region | ✅ |
| Load test with k6 sized to deployment targets (`C_critical` applies, `C_peak` WebSocket connections) | ✅ |
| MFA enforced for all admin users | ✅ |
| Penetration test by an external party | ✅ |

After this milestone: the system can absorb the design's peak traffic with confidence.

---

## What this delivery model is NOT

- **Not "MVP first, polish later"** — every milestone ships with proper observability, CI/CD, security, and event schemas. There is no "we'll add tests after launch" path.
- **Not waterfall** — milestones are independent vertical slices; you can ship them in roughly this order, but the foundation work (Milestone 0) has to come first.
- **Not "do it all in parallel"** — services depend on infra; features depend on Identity + Companies + Jobs being in place. Order matters.

## What to NOT build (out of scope for the delivery plan)

- Mobile app (responsive web first; native later if demand justifies)
- AI / LLM features (resume summarization, chatbot)
- Multi-language UI
- White-label custom domains for companies
- Voice/video chat
- Saved searches / job alerts via email
- Recruiter ATS features beyond what's specified

These are real products in their own right. They get their own design plans when prioritized.

## Per-milestone definition of done

A milestone is done when:

- All acceptance criteria are met
- All services involved have green CI
- Deployed to staging via ArgoCD
- Smoke-tested in staging
- Observability is in place — dashboards, alerts, traces
- Documentation updated (service README + this folder if architecture changed)
- Deployed to production via ArgoCD
- Verified in production with synthetic monitoring

Anything less, and we are accumulating debt instead of shipping.
