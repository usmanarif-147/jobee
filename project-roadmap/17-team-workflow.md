# 17 — Team Workflow (Multi-Developer Collaboration)

CI/CD is **mandatory infrastructure**. Every merge to main runs through a green pipeline before reaching users. There is no "deploy by hand" path.

## The setup

- **Code hosting:** GitHub (single monorepo; ownership enforced by path-scoped CODEOWNERS so each service's PRs auto-request the right reviewers)
- **Issue tracking:** GitHub Issues + GitHub Projects (kanban board)
- **Code review:** GitHub Pull Requests with mandatory approvals
- **CI:** GitHub Actions (one pipeline per repo, runs on every PR and every merge)
- **CD:** GitHub Actions builds Docker image → ArgoCD deploys to K8s
- **Container registry:** GitHub Container Registry (GHCR)
- **Communication:** Slack or Discord (one channel per service / topic)
- **Documentation:** GitHub Wiki + this `project-roadmap/` folder + service READMEs

## Repo layout — monorepo

**One repo, per-service folders.** Each service still has its own deploy cadence, CI, and ownership — those are enforced by **path filters** and **CODEOWNERS**, not by separate repos. See `project-structure/01-folder-tree.md` for the full tree.

```
jobee/
├── services/
│   ├── identity-service/        # Laravel
│   ├── companies-service/       # Laravel
│   ├── jobs-service/            # Laravel
│   ├── payment-service/         # Laravel + Cashier
│   ├── notification-service/    # Laravel + Horizon
│   ├── chat-service/            # Laravel Reverb
│   ├── media-service/           # Laravel
│   ├── resume-parser-service/   # Python + FastAPI
│   ├── search-service/          # Laravel (Meilisearch wrapper)
│   └── reporting-service/       # Laravel scheduler
├── web/
│   ├── public-web/              # Nuxt
│   ├── company-web/             # Vue
│   └── admin-web/               # Vue
├── infra/                       # Terraform / Helm / K8s manifests / ArgoCD apps
├── event-schemas/               # Versioned schemas for every Kafka topic
├── packages/                    # Shared libraries (outbox helper, OTel config, Kong client)
├── docs/
├── scripts/
├── .github/workflows/           # One workflow file per service, path-filtered
├── docker-compose.yml
└── Makefile
```

How independence is preserved without separate repos:

- **One `main` branch** for the whole repo. No long-lived branches.
- **Path-scoped CI** in `.github/workflows/`. Each service has its own workflow:
  ```yaml
  on:
    pull_request:
      paths: [ "services/identity-service/**", "packages/**" ]
  ```
  A change in `services/jobs-service/` never triggers Identity's pipeline.
- **Path-scoped CODEOWNERS** so a Jobs Service PR auto-requests Jobs reviewers; an `infra/` PR auto-requests platform reviewers.
- **Per-service image tags** of the form `identity-service:v0.42.0` — one image per service, built from the same repo.
- **Per-service semantic versioning** maintained via `release-please` configured with one component per path (each service tracks its own `MAJOR.MINOR.PATCH` history).
- **Shared libraries** live in `packages/` and are consumed via Composer / npm / pip path-references. No extra repos, but still versioned within the monorepo so a breaking change to a shared library is a deliberate bump, not an accident.
- **Concurrency keys** in workflows scope CI runners per service so parallel work doesn't queue behind unrelated jobs.

## Branching strategy — Trunk-based development

- One long-lived branch: `main`
- Every change goes through a short-lived feature branch: `feat/...`, `fix/...`, `chore/...`
- Branches live <2 days. Long branches = merge hell.
- Merging requires **PR + at least 1 review + green CI**

This is simpler than Git Flow and matches modern industry practice.

## PR rules (enforced by GitHub branch protection)

A PR cannot merge unless:

- [x] At least 1 reviewer approves
- [x] All CI checks pass (tests, linter, security scan)
- [x] No unresolved review comments
- [x] Branch is up-to-date with `main`

For solo work, the second reviewer rule is relaxed — but CI must still pass.

## What CI runs on every PR (per service)

1. Checkout
2. Install deps
3. Linter (PHP CS Fixer / ESLint / black)
4. Static analysis (PHPStan / Psalm / mypy)
5. Unit + feature tests (Pest / PHPUnit / Jest / pytest)
6. Validate any new event schemas against the schema registry
7. Security scan (Trivy on Docker image; composer/npm/pip audit)
8. Build Docker image (pushed only on `main` merges)

Target: every CI run completes in <5 minutes.

## What CI runs after merging to `main`

1. Build a tagged Docker image (`v0.42.0`)
2. Push to GHCR
3. Open PR in the `infra` repo bumping the image tag in the Helm values for that service
4. The infra PR runs its own CI (validates manifests)
5. After approval and merge, ArgoCD detects the change and syncs the cluster
6. Pods roll out with zero downtime

This is the **GitOps** pattern — the cluster is whatever Git says. Manual `kubectl apply` is forbidden in production.

## Code review checklist

For reviewers:

- [ ] Does it solve the actual problem in the ticket?
- [ ] Are there tests covering the new behavior?
- [ ] Are edge cases (slot capacity, idempotency, auth) handled?
- [ ] Are there obvious performance issues (N+1 queries, no cache for hot path)?
- [ ] Are migrations backwards-compatible?
- [ ] Does it follow the codebase style?
- [ ] Are secrets / env vars handled correctly (no hard-coded keys)?
- [ ] Is there observability (logs, metrics) for the new code?

## Conventional commits

Commit messages follow:

```
type(scope): short summary

longer body if needed
```

Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `perf`. Helps auto-generate changelogs and version bumps.

## Versioning

Semantic versioning per service: `MAJOR.MINOR.PATCH`. Bump:

- `MAJOR` for breaking API changes
- `MINOR` for new features (backwards-compatible)
- `PATCH` for bug fixes

Tools like `release-please` automate this from commit messages.

## Pre-commit hooks (developer machines)

Install **pre-commit** (Python tool) or **lefthook** (Go tool) — runs:

- Linter
- Static analyzer
- Trailing whitespace cleaner
- Secrets scanner (`gitleaks`)

Catches obvious issues before pushing → CI saves time.

## Handling cross-service changes

A feature that touches multiple services (e.g., Jobs + Notification + Search):

1. Define / update the event schema in `event-schemas` repo first; merge it
2. Open a PR in the **producing** service (e.g., Jobs) emitting the new event behind a feature flag
3. Open PRs in **consuming** services (Notification, Search) handling the new event
4. Merge consumers first (handling an event that's never produced is a no-op)
5. Merge producer; toggle feature flag on
6. Roll the flag from 0% → 10% → 100%

Feature flags decouple deploy from release. Use a tool like Unleash, Flagsmith, or GrowthBook.

## Migrations and schema evolution

When a service adds a DB column or a new event-payload field:

- **Backwards-compatible first**: add the column / field as optional
- Deploy and let other services adapt
- Then remove the old behavior in a separate deploy

For Kafka event schemas: the schema registry enforces backward compatibility. Breaking changes require a new `schema_version` and a migration window. **Never** rename or drop something in a single deploy.

## Onboarding a new developer

A new dev should be able to:

1. Clone the monorepo
2. Run `docker compose up -d`
3. Be running locally within 30 minutes

If they can't, the onboarding docs are wrong — fix them.

The `README.md` of each service folder must include:

- What the service does
- How to run it locally
- How to run tests
- How to make a PR
- Pointer to this `project-roadmap/` for system context

## Slack / Discord conventions

- One channel per service for discussion
- One channel `#alerts` where automated alerts land
- One channel `#incidents` for active production issues — async-first, but can convert to a video call when needed
- One channel `#standup` for daily updates if doing sync standups

## Definition of Done

A feature is done when:

- Code is merged
- Tests are green
- Deployed to production
- Verified in production (smoke test)
- Observability is in place (logs/metrics for the new behavior)
- Documentation is updated
- Stakeholder confirms it works

Anything less, and we're shipping debt.
