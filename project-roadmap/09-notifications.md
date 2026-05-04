# 09 — Notification Service (Async Only)

## Scope — what this service does

The Notification Service is **purely async**. It consumes events from Kafka, decides who should be told what, and dispatches via:

- **FCM push** for mobile / browser push
- **Email** — transactional (Postmark) or bulk (AWS SES)
- **In-app notifications** — DB rows that frontends fetch via API

It does **not** handle WebSocket. WebSocket-based realtime push lives in Chat Service (file 08), which subscribes to events emitted by Notification Service when an in-app notification is created.

```
Kafka topics (jobs.applications, identity.users, payments.subscriptions, ...)
                  │
                  ▼
        Notification Service (consumers)
   ┌──────────────┼──────────────┐
   ▼              ▼              ▼
  FCM          Email          In-app DB row
 (Firebase)   (Postmark      (read by frontends
              / SES)          via REST)
                                    │
                                    ▼
                       Notification Service emits
                       `notifications.in_app_created`
                                    │
                                    ▼
                       Chat Service pushes a
                       WebSocket event to update
                       the bell icon live
```

## Channels

| Channel | When | Provider |
|---|---|---|
| FCM push | New application, new chat message, time-sensitive alerts | Firebase Cloud Messaging |
| Transactional email | Account confirmation, password reset, single-event notifications | Postmark |
| Bulk / broadcast email | Admin announcements, recruiter mass emails (1–1000 recipients) | AWS SES |
| In-app | Bell-icon dropdown — frontend reads via REST | DB row in `notifications` table |

## Routing — who gets what

Each user has notification preferences (per-channel, per-event-type). Defaults:

| Event | Admin | Company users | Applicants |
|---|---|---|---|
| New application | — | FCM + email + in-app | — |
| Application status change | — | — | Email + in-app |
| Subscription expiring | — | Email | — |
| Platform announcement | Email | Email | Email (only critical) |
| New chat message | FCM | FCM | — |

Preferences live in a `notification_preferences` table.

## Fan-out for multi-recipient events

When `ApplicationCreated` arrives, the company may have many users with the role "receive applications":

1. Call Companies Service: "give me all users in company X with permission `applications.view`"
2. Look up each user's FCM device tokens (a user may have many)
3. Build a single batched FCM payload (FCM accepts up to 500 tokens per call) and send
4. Queue one email job per recipient (parallelised across workers)

Batching FCM saves cost and avoids rate limits.

## Bulk email broadcast (1–1000 recipients)

A 1000-recipient email cannot be sent inline. The flow:

1. Sender (admin or company) submits a `BroadcastJob` (subject, body template, recipient list, send_at)
2. Notification Service stores the job, publishes a `BroadcastQueued` event
3. The broadcast worker chunks the recipient list into chunks of 50
4. Each chunk is queued as a separate job
5. Workers send each chunk via SES (parallel)
6. Each chunk reports success/failure rates back to the parent `BroadcastJob` row
7. Frontend can show a live progress bar

A 1000-recipient broadcast finishes in under a minute.

## Email deliverability essentials

- SPF, DKIM, DMARC on `job-hunter.com`
- Separate sending domains: `notify.job-hunter.com` (transactional) vs `marketing.job-hunter.com` (bulk) — protects transactional reputation
- Bounce + complaint webhooks from SES → automatically suppress addresses that hard-bounce
- Every marketing email has a one-click unsubscribe link

## FCM device token management

- Mobile/web apps register their FCM token on login
- Tokens stored in `device_tokens` table (user_id, token, platform, last_used_at)
- On send failure (`InvalidRegistration`, `NotRegistered`), the token is deleted — no zombie tokens
- Token refresh handled by the app SDK; the app re-registers when it changes

## In-app notifications

- A row in `notifications` per user per event
- Frontend calls `GET /notifications` (paginated) and `GET /notifications/unread-count`
- When a row is created, Notification Service publishes `notifications.in_app_created` to Kafka
- Chat Service consumes and pushes a WebSocket event to the user → bell icon updates instantly

## Queueing & retries

- All work runs on Laravel queues (Horizon for visibility)
- Retries: 3 attempts with exponential backoff (10s, 1min, 5min)
- Final failure → moved to a dead-letter Kafka topic for inspection
- Idempotency: every notification has a UUID; providers deduplicate by message ID

## Rate limits

- A company can broadcast at most 5,000 emails/day on the standard plan
- Per-user FCM throttle to avoid spam
- Per-IP rate limits at the API gateway prevent abuse on the broadcast endpoint

## Observability

- Every notification logs: `event_id`, `user_id`, `channel`, `provider`, `status`, `latency`
- Grafana dashboard: send rate, delivery rate, bounce rate per domain, queue depth
- Alert if delivery rate drops below 95% for any channel
- Alert if `notifications` consumer lag in Kafka exceeds 1 minute
