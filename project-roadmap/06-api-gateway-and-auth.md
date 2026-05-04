# 06 — API Gateway & Auth

## The gateway — Kong

One entrypoint for the three frontends. Kong handles:

- **Routing** by hostname / path to the right backend service
- **Auth** — validates tokens by calling Identity Service's `/introspect` endpoint (cached briefly in Redis)
- **Rate limiting** — per IP, per user, per endpoint
- **Request ID injection** — every request gets a unique `X-Request-ID` for distributed tracing
- **CORS** — only the three frontends allowed
- **Logging** — every request logged with route, status, latency, user

## Routing table

| Incoming | Routed to |
|---|---|
| `api.job-hunter.com/v1/auth/*` | Identity Service |
| `api.job-hunter.com/v1/users/*` | Identity Service |
| `api.job-hunter.com/v1/companies/*` | Companies Service |
| `api.job-hunter.com/v1/jobs/*` | Jobs Service |
| `api.job-hunter.com/v1/applications/*` | Jobs Service |
| `api.job-hunter.com/v1/billing/*` | Payment Service |
| `api.job-hunter.com/v1/notifications/*` | Notification Service |
| `api.job-hunter.com/v1/chat/*` (REST) | Chat Service |
| `wss.job-hunter.com` (WebSocket) | Chat Service |
| `api.job-hunter.com/v1/media/*` | Media Service |
| `api.job-hunter.com/v1/search/*` | Search Service |
| `api.job-hunter.com/v1/reports/*` | Reporting Service |
| `api.job-hunter.com/v1/parser/*` (internal) | Resume Parser Service |
| `api.job-hunter.com/v1/billing/webhooks/stripe` | Payment Service (no auth, signature-verified) |

WebSockets get their own subdomain to keep gateway routing simple.

## Identity Service — the source of truth for auth

Identity Service owns:

- Users, signup, login, email verification, password reset, MFA
- Roles and permissions (via spatie/laravel-permission)
- Sessions (Sanctum cookie for SPAs)
- API tokens (Sanctum personal access tokens)
- Cross-service JWTs (short-lived, RS256-signed)

Three login realms; **same backend**, three guards:

| Realm | Guard | Cookie scope |
|---|---|---|
| Super admin | `admin` | `admin.job-hunter.com` |
| Company user | `company` | `company.job-hunter.com` |
| Applicant | `web` | `job-hunter.com` |

Cookies cannot leak across realms.

## How Kong validates a request

1. Frontend calls `api.job-hunter.com/v1/jobs` with a Sanctum cookie (or Bearer JWT for mobile)
2. Kong's auth plugin extracts the credential
3. Kong looks up the credential in **Redis cache** (5–10 second TTL)
4. If cache miss, Kong calls Identity Service's `POST /v1/auth/introspect`
5. Identity Service responds with: `{ user_id, roles, permissions, expires_at }` (or 401)
6. Kong caches the response, attaches user context as headers (`X-User-ID`, `X-User-Roles`), and forwards to the target service
7. The target service trusts these headers (Kong is the only path in)

Caching keeps the auth path fast even at high QPS. TTLs are short so revoked tokens become invalid quickly.

## Cross-service service-to-service auth

Internal calls (e.g., Resume Parser fetching a file from Media Service) use a different mechanism:

- Each service has a service account in Identity
- Services authenticate via mTLS or signed JWT (issued at startup, refreshed periodically)
- Calls travel through Kong (so they're traced and rate-limited) or directly within the cluster

Internal-only routes are blocked at Kong from external IPs.

## Authorization — at the service layer

Kong checks "is this token valid?" Services check "is this user allowed to do this?"

Pattern:

- `X-User-Roles` header is on every request
- Service uses Laravel policies / gates: `$user->can('jobs.create', $company)`
- Permissions are namespaced per realm: `admin.support`, `company.recruiter`, `applicant.basic`
- Multi-tenant data: every Companies / Jobs query filters by the resolved `company_id` from the URL

## Multi-tenancy: companies have their own users

A company has many users via Companies Service's `company_users` table. Each company-user has a role within that company.

Per-request resolution (cached for the duration of the request):

1. URL contains `/{company-uuid}`
2. Companies Service resolves: does this user belong to this company? With what role?
3. The role is added to the request context
4. Downstream services use it for fine-grained checks

## Rate limiting

| Scope | Limit |
|---|---|
| Per IP | 100 req/min |
| Per authenticated user | 600 req/min |
| Login endpoint | 5 attempts / 15 min per IP and per email |
| Bulk email broadcast | 10 broadcasts/hour per company |
| Application submit | 5 applications/min per applicant |

Counters in Redis. Kong's rate-limit plugin handles increment + check.

## CORS

- Configured at Kong only (one place)
- Allowed origins: the three frontend domains
- Credentials allowed (cookies)

## Request tracing

Kong injects `X-Request-ID` on every request. Every backend service logs it. Every emitted Kafka event includes it. When debugging, grep one ID across every service log to see the full journey including async hops.

## Failure modes

| Failure | Mitigation |
|---|---|
| Kong down | Run 3+ Kong instances behind a Cloudflare LB. The gateway is the single point of entry — never run only one. |
| Identity Service down | Kong's auth cache covers brief outages; expired cache → 503 with retry-after. Identity must have its own HA setup. |
| Backend service down | Kong returns 502 for that route; other routes unaffected. Circuit breaker plugin in Kong avoids hammering a dead service. |
| Slow Identity introspection | Aggressive Redis caching; degrade gracefully if Identity is slow (use stale cache value briefly). |

## High availability for Identity Service

Identity Service is the critical path — every request passes through it (via Kong's introspection). Production setup:

- 3+ pods behind a load balancer
- Multi-AZ deployment
- Read replica for the database
- Aggressive caching at Kong
- Outage runbook well-rehearsed
