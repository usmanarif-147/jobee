# 20 — Security

The non-exhaustive but high-impact list. Security is layered — every layer assumes the layer above might fail.

## Layer 1 — Edge

- **Cloudflare** in front of everything: free DDoS protection, basic WAF, rate-limiting at the edge
- Force HTTPS via HSTS (longest age, include subdomains)
- TLS 1.3 only (disable old protocols)
- SSL certificates auto-renewed (Let's Encrypt or Cloudflare-issued)

## Layer 2 — API Gateway

- All requests authenticated (or explicitly marked public)
- Per-IP and per-user rate limits
- CORS strict — only our three frontends allowed
- Request size limits (e.g., 25MB max — beyond that is suspicious)
- Block unusual user agents and known bad patterns

## Layer 3 — Application

### Authentication (Identity Service is the single source of truth)

- Sanctum cookie-based for SPAs (httpOnly, Secure, SameSite=Lax)
- Bcrypt for password hashing (Laravel's default; cost factor ≥ 12)
- Email verification on signup
- Forgotten-password tokens expire in 60 minutes, single-use
- Rate-limit login attempts (5 per 15 minutes per IP and per email)
- Lockout after 10 failed attempts on the same account
- MFA (TOTP) mandatory for admin users; optional for company users

### Cross-service authentication

- Internal calls between services use **short-lived JWTs** issued by Identity Service
- Each service validates JWTs locally (signature with Identity's public key) — no extra hop on every internal call
- JWTs include `user_id`, `roles`, `permissions`, `expires_at`
- Services trust the `X-User-ID` and `X-User-Roles` headers Kong injects (because only Kong can reach internal services)
- Inter-service calls also carry a service identity (mTLS or service-account JWT) so Service A can prove it's Service A when calling Service B

### Authorization

- spatie/laravel-permission for RBAC
- Policy classes guard every action (`$user->can('jobs.create', $company)`)
- Defense in depth: gateway-level checks + service-level checks + DB constraints
- Multi-tenant data: every query for company data filters by `company_id` — nothing leaks across companies

### Input validation

- Laravel Form Requests on every endpoint — never trust client input
- Type and length checks on every field
- Strict file mime checks (sniff content, don't trust headers)
- Reject HTML in all string inputs by default (escape on output)

### SQL injection

- Use Eloquent / parameterized queries everywhere
- **Never** concatenate user input into raw SQL
- Read replica connections must use the same parameterized layer

### XSS

- Blade auto-escapes by default (`{{ $var }}`); raw output (`{!! $var !!}`) only with explicit sanitization
- Content-Security-Policy headers — restrict scripts/images/connect to known origins
- Sanitize rich-text fields (job descriptions) with HTMLPurifier or similar

### CSRF

- Sanctum / Laravel handles CSRF tokens automatically for cookie-based auth
- API token auth is not CSRF-vulnerable but should still verify Origin/Referer

### IDOR (Insecure Direct Object Reference)

- Use UUIDs (not auto-increment IDs) in URLs for objects users own
- Always verify ownership before showing/modifying any resource
- Test every endpoint by tampering with the ID — should 403/404

## Layer 4 — Data

### Encryption at rest

- Postgres encrypted disks (RDS does this by default)
- S3 with SSE-S3 (server-side encryption)
- Backups encrypted

### Encryption in transit

- TLS between every service hop (in K8s with service mesh; until then, between gateway and origins)
- TLS to Postgres and Redis (RDS/ElastiCache support this)

### Sensitive fields

- Never log passwords, tokens, payment details, or full PII
- Mask emails/phones in logs (`a***@example.com`)
- Resumes contain PII — restrict access to the company that received the application + super admins (with audit log)

### Database isolation

- DB user per service (least privilege)
- Read-only DB user for read replicas
- Network ACLs: only the service's pods can reach its DB
- Each service's DB is in its own RDS cluster — no shared DB across services

### Event payload validation

- Every event published to Kafka is validated against its registered schema (file 22)
- Consumers reject events with unknown / mismatched schemas
- Events with PII fields (e.g., resume application) are explicitly marked; consumers handle them with extra care
- Sensitive events (e.g., `PasswordReset`) are emitted to topics with restricted ACLs — only authorized consumer groups can read

### Backups

- Encrypted at rest
- Stored in a separate AWS account (so a compromised primary account can't delete backups)

## Layer 5 — Infrastructure

- IAM least-privilege per service
- No long-lived AWS access keys for humans — use SSO
- Container images scanned in CI (Trivy)
- Dependencies scanned in CI (composer audit, npm audit, pip-audit, Snyk)
- Secrets in Secrets Manager / Vault — never in env files in Git, never in container images
- K8s pod security policies — no privileged containers, read-only root filesystems where possible
- Network policies — services can only reach the services they actually need to

## Operational security

- All access to production behind SSO + MFA
- Audit logs for admin actions (who deleted that company?)
- Quarterly access reviews — does this person still need this permission?
- On-call rotation with runbooks for security incidents

## Specific concerns for THIS app

### Bulk email abuse

- A compromised company account could send 1,000 spam emails
- Mitigations: per-company daily limit; admin approval for first-time bulk emails; monitor bounce/complaint rates

### Resume PII leakage

- Resumes contain phone numbers, addresses, sometimes ID numbers
- Access strictly limited to the receiving company + admin
- No CDN caching of resumes
- Audit log every resume view by an admin

### Stripe webhook spoofing

- Verify the `Stripe-Signature` header on every webhook
- Reject any unsigned or wrongly-signed payload
- Webhooks live on a dedicated endpoint with no other auth

### File-upload attacks

- Mime sniffing to detect spoofed files
- ClamAV virus scan
- Strict size limits
- Files served via presigned URLs only — never publicly readable
- Filename never used directly (UUID rename on save)

### Account-takeover via password reset

- Password-reset tokens single-use, short-lived, sent only to the verified email
- Notify the user when the password is changed
- IP / location anomaly detection (later)

## Security checklist before each release

- [ ] No new endpoints without auth (or explicitly marked public)
- [ ] No new endpoints without input validation
- [ ] No new dependencies added without audit
- [ ] No new admin actions without audit logging
- [ ] No new file uploads without size + mime validation + virus scan
- [ ] No new emails without rate limiting
- [ ] No new secrets without using Secrets Manager

## What to outsource (don't roll your own)

- Card handling → Stripe
- Email → Postmark / SES
- Authentication libraries → Sanctum, never custom
- Encryption primitives → libsodium (libraries that wrap it)
- WAF → Cloudflare

## When something goes wrong (incident response)

1. **Detect** — alerts fired, or user reported it
2. **Triage** — is it real? what's the blast radius?
3. **Contain** — disable the affected feature; revoke tokens; block IPs
4. **Eradicate** — fix the root cause
5. **Recover** — restore service; verify
6. **Learn** — blameless post-mortem; what gap did this expose?

Have a runbook for common incidents (compromised admin account, S3 bucket leak, DDoS, email blacklisting). Run a tabletop exercise once a quarter.
