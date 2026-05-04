# 14 — Caching & Search

## Caching strategy — what to cache, where, and when to invalidate

Most performance problems are solved by caching the right thing. Most cache bugs are caused by caching the wrong thing.

### What goes in cache (Redis)

| Data | Key pattern | TTL | Invalidation |
|---|---|---|---|
| Job listing pages | `jobs:list:{filters_hash}` | 60 seconds | TTL only — listings tolerate slight staleness |
| Single job page | `job:{id}` | 5 minutes | Invalidate on `JobUpdated` event |
| Company public profile | `company:{uuid}:public` | 5 minutes | Invalidate on profile update event |
| Skills list (autocomplete) | `skills:all` | 1 hour | Invalidate when admin adds a skill |
| User session | `session:{id}` | session lifetime | Cleared on logout |
| User permissions | `auth.user:{id}` | 5 minutes | Invalidate on role/permission change event |
| Active subscription check | `sub:active:{company_id}` | 60 seconds | Updated on `SubscriptionActivated` / `SubscriptionExpired` |
| Counters (views, clicks) | `job:{id}:views` | persistent until flushed | Flushed to DB every minute |
| Rate-limit counters | `rate:{ip}:{route}` | 1 minute | TTL |
| Kong auth introspection | `kong:auth:{token_hash}` | 5 seconds | TTL only |

### Cache pattern: cache-aside (lazy loading)

Standard pattern in every service: check cache → on miss, read DB → set cache with TTL → return.

### Stampede protection

If 1,000 users request the same uncached page at once, all 1,000 hit Postgres. Solutions:

- **Per-key locks**: only one process recomputes; others wait briefly
- **Soft-TTL** (Laravel `Cache::flexible`): serve stale value while one process refreshes in background
- Use both for hot pages (homepage, popular job listing)

### Event-driven cache invalidation

Services subscribe to relevant Kafka topics to invalidate caches reactively:

- Companies Service consumes `payments.subscriptions` → updates `sub:active:{company_id}`
- Search Service consumes `jobs.jobs` → updates Meilisearch index entries

This is more accurate than time-based expiry alone.

### What we explicitly do NOT cache

- Application slot counts (always read live from DB or Redis counter)
- Resume parse results in transit
- Anything in the admin panel (low traffic, freshness matters more)

### Cache layer order

```
Browser (HTTP cache headers)
  → Cloudflare CDN (static assets, public images, public job listings)
    → Nginx micro-cache (1-second cache on hot routes)
      → Redis (application cache)
        → Postgres (source of truth)
```

Each layer absorbs traffic so the lower layers see less.

---

## Search — Search Service in front of Meilisearch

### The wrapper pattern

The frontend never hits Meilisearch directly. Instead:

```
Frontend → Kong → Search Service → Meilisearch
                  (auth, tenancy,
                   ranking config)
```

Why a wrapper:

- The Meilisearch API key cannot leak to browsers
- Tenancy filters (admins see closed/draft jobs, public doesn't) need server enforcement
- Custom ranking, query rewriting, A/B tests live in our code
- A unified search surface even if we add a vector / semantic search backend later

Search Service is a small Laravel app. Stateless. Scales horizontally. No database of its own — Meilisearch is the store.

### Why Meilisearch (not Elasticsearch)

- Single binary, easy to operate
- Fast, fuzzy, typo-tolerant out of the box
- Plenty for the scale of this product
- Lower operational cost than Elasticsearch
- Can be replaced by Elasticsearch / OpenSearch later by changing the wrapper internals — frontend API stays stable

### What we index

A flattened "JobDocument" per published job:

- `id`, `title`, `description` (truncated), `company_name`, `company_uuid`, `location`, `tags`, `skills[]`
- `posted_at`, `apply_before`, `salary_range`
- `applicant_count`, `is_open`

Resumes and applications are **not** indexed (privacy-sensitive).

### Keeping the index in sync — event-driven

Search Service consumes:

- `jobs.jobs` (`JobCreated`, `JobUpdated`, `JobClosed`) → upsert / delete in Meilisearch
- `jobs.applications` (`ApplicationCreated`) → increment `applicant_count`
- `companies.companies` (`CompanyUpdated`) → update denormalized company name on jobs

If Meilisearch is down, events sit in Kafka and are processed when it recovers.

### Reindex on schema change

A scheduled job in Reporting Service can reindex the entire `jobs` table from scratch by replaying the topic from the beginning (Kafka's superpower). Reindexing 2M jobs takes minutes; do it during low-traffic windows.

### Search filters and facets

- Skills (multi-select)
- Location
- Salary range
- Posted date range
- Company

Meilisearch supports filterable attributes natively. Search Service exposes them through a clean public API.

### Ranking

Default Meilisearch ranking is good. Tweaks worth considering:

- Boost `title` matches over `description` matches
- Boost recently posted jobs
- Penalize closed jobs (don't hide — let them appear lower)

These are configured in Search Service, not Meilisearch directly, so we can iterate without touching the backing store.

### Privacy

The Meilisearch instance is **not exposed to the public internet**. It's only reachable from the Search Service's pods. All search requests go through Search Service, which:

- Authenticates the user (via Kong-injected headers)
- Applies tenancy filters
- Forwards to Meilisearch with those filters baked in
- Returns clean JSON to the client
