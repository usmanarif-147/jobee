# 19 — Production Deployment

What changes from local Docker Compose → production.

## The big shifts

| Local | Production |
|---|---|
| Docker Compose (one host) | Kubernetes (managed, multi-node, multi-AZ) |
| Bind-mounted code | Code baked into immutable Docker images |
| MinIO | AWS S3 |
| Mailhog | Postmark + AWS SES |
| Self-hosted Postgres | AWS RDS for Postgres (one cluster per service) |
| Self-hosted Redis | AWS ElastiCache |
| Self-hosted Kafka | AWS MSK or Confluent Cloud |
| Self-signed / no SSL | Cloudflare-issued certs at the edge; cert-manager inside cluster |
| Stripe CLI tunnel | Real Stripe webhook URL |
| `.env` file | AWS Secrets Manager |
| `docker compose logs` | Loki + Grafana |
| Manual `docker compose up` | ArgoCD GitOps deploy |

## Hosting — AWS or DigitalOcean

Two viable production targets:

### AWS (recommended)
| Layer | Service |
|---|---|
| Compute | EKS (managed Kubernetes) |
| Database | RDS for Postgres (per service) |
| Cache | ElastiCache for Redis |
| Object storage | S3 |
| Event bus | MSK (Managed Streaming for Kafka) |
| Load balancer | ALB |
| DNS | Route 53 (or Cloudflare DNS) |
| Email | SES + Postmark (Postmark for transactional) |
| Secrets | Secrets Manager |
| Schema registry | Self-hosted Karapace OR AWS Glue Schema Registry |

### DigitalOcean (alternative — simpler ops)
| Layer | Service |
|---|---|
| Compute | DOKS (managed Kubernetes) |
| Database | DO Managed Postgres |
| Cache | DO Managed Redis |
| Object storage | Spaces (S3-compatible) |
| Event bus | Kafka via Aiven (since DO doesn't have managed Kafka) |
| Load balancer | DO Load Balancer |
| DNS | Cloudflare |
| Email | Postmark + SES |

Both are full-scale capable. Pick based on team familiarity and vendor preference.

## DNS and SSL

- **DNS at Cloudflare** — proxies traffic, hides origin IPs, free SSL at the edge
- All four hostnames (`job-hunter.com`, `company.*`, `admin.*`, `api.*`, `wss.*`) point to the load balancer
- Cloudflare's "Full (strict)" SSL mode → end-to-end encrypted
- Inside the cluster: cert-manager + Let's Encrypt for inter-service TLS

## Image pipeline

Every merge to `main` that touches `services/<svc>/**` (path-filtered in `.github/workflows/<svc>.yml`):

```
GitHub Actions (per-service workflow):
  1. Run that service's tests + linters + schema validation
  2. Build image for that service only
  3. Tag with commit SHA + per-service semantic version (e.g. identity-service:v0.42.0)
  4. Push to GHCR
  5. Auto-commit (or open PR) updating infra/helm/<svc>/values.yaml in the same repo

Infra changes (under infra/**):
  1. CI validates Helm + K8s manifests
  2. PR auto-merges after approval (or commit goes straight to main if auto-committed)

ArgoCD (watches infra/):
  1. Detects the change
  2. Syncs the cluster — rolling update for that service only
  3. Old pods drained as new pods pass readiness probes
```

Path filters ensure a one-file change in `services/jobs-service/` never rebuilds the other nine images. Zero-downtime deploys are free with this pattern.

## Database migrations on deploy

Migrations run via a Kubernetes `Job` (or Helm pre-install hook) before the rollout starts. The Job exits success → new pods start.

Strict rule: **migrations are backward-compatible.** Old pods still running during the rollout must continue working. Any rename/drop is split into two deploys.

## Rolling update strategy

Each service's Deployment manifest sets:

- `maxSurge: 25%`
- `maxUnavailable: 0`

Pods are added new → old ones drained → users never see downtime.

## Health checks

Every service exposes:

- `livenessProbe` — `/health/live`
- `readinessProbe` — `/health/ready` (verifies DB, Redis, Kafka reachable)
- `startupProbe` — for slow-starting services

K8s only routes traffic to pods that pass `readinessProbe`.

## Secrets management

1. Secrets stored in **AWS Secrets Manager**
2. **External Secrets Operator** in K8s pulls them and mounts them as K8s Secrets
3. K8s injects them into pod environment variables at runtime
4. Code reads them as normal env vars

Never in Git. Never in container images. Never in logs.

## Backups

- **Postgres (each service):** RDS automated backups + 7-day retention; weekly off-site dump to S3 Glacier; cross-region copy
- **S3:** versioning + cross-region replication for resumes
- **Kafka:** events have retention (typically 7–30 days); critical topics have longer retention + tiered storage
- **Redis:** stateful only as a cache — not backed up (rebuild from sources)

Restore tested **monthly**. A backup that has never been restored is not a backup.

## Logging in production

- Stdout from each pod → Vector / Promtail → Loki
- Loki retention: 30 days
- Grafana dashboards saved as YAML in `infra` repo (versioned)

## Metrics in production

- Each service exposes `/metrics` (Prometheus format)
- Prometheus scrapes every 15 seconds
- Grafana dashboards: API latency, queue depth, DB QPS, WebSocket connections, Kafka consumer lag, Stripe webhook health

## Alerts in production

PagerDuty (or Opsgenie) wired to Prometheus Alertmanager:

- Service down >2 min
- p99 latency >2s for 5 min
- Error rate >5%
- DB primary unreachable
- Kafka consumer lag > 1 minute on hot topics
- Outbox depth > 1000
- Schema validation failures

## Security hardening in prod

- Cloudflare WAF
- Force HTTPS everywhere (HSTS preload)
- IAM least-privilege per service (each service has its own IAM role)
- Rate-limit aggressively at the gateway
- AWS GuardDuty for anomaly detection
- CIS-benchmark scan on K8s cluster
- Container images scanned in CI (Trivy)
- Dependency scanning in CI

## Disaster recovery

- RTO: 1 hour
- RPO: 5 minutes (Postgres PITR; Kafka retention covers most lag)
- Multi-AZ everything
- Infrastructure-as-Code (Terraform) so the entire stack can rebuild in a different region in <1 hour
- Game-days quarterly: simulate a region failure, practise the runbook

## Cost note

A 10-service production system on AWS EKS + RDS + MSK + ElastiCache is meaningful infrastructure. Practising it locally is free. Detailed cost projection is out of scope for these design files — covered separately.
