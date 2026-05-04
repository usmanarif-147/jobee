# 12 — Scheduled Jobs (Cron, Sweepers, Reports)

## Where scheduling lives

Scheduling is **distributed across services** — each service runs its own scheduled jobs for things it owns. The Reporting Service owns the cross-service report generators that pull from many topics.

| Service | What it schedules |
|---|---|
| Identity | Cleanup of expired email-verification tokens, password reset tokens |
| Companies | Subscription cache reconciliation against Payment events |
| Jobs | Job auto-close sweeper, view counter flush |
| Payment | Stripe reconciliation, expiry reminders, expiry sweeper |
| Notification | Bounce / complaint cleanup, dead-letter reprocessing |
| Media | Orphan-file cleanup (uploads never confirmed), retention enforcement |
| Reporting | Daily / weekly / monthly platform reports |

Each service has its own Kubernetes `CronJob` resources for these. No single "cron node" exists.

## What runs on a schedule

| Job | Frequency | Purpose |
|---|---|---|
| **Subscription expiry reminders** | Hourly | Find subs expiring in 7/3/1 days, send emails |
| **Subscription expiry sweeper** | Hourly | Mark expired subs, disable their jobs |
| **Job auto-close sweeper** | Every minute | Close jobs past `apply_before` or at applicant cap |
| **Counter flush** | Every minute | Move `job_views` / `job_clicks` from Redis to Postgres |
| **Stripe reconciliation** | Daily | Pull subscription list from Stripe, fix drift |
| **Daily platform report** | 02:00 UTC daily | Generate PDF/CSV; email to admins |
| **Weekly platform report** | Mondays 02:00 UTC | Same, weekly slice |
| **Monthly platform report** | 1st of month 02:00 UTC | Same, monthly slice |
| **Cold-data archiver** | Weekly | Move 90+ day-old views/clicks to S3 Glacier |
| **Health probe** | Every 5 minutes | Pings every service; alerts if unhealthy |
| **Email warmup throttler** | Daily | Adjusts daily send-limit for new sending IPs |
| **Skill dictionary cleanup** | Weekly | Reviews NER-discovered skills; admin can promote/reject |

## How scheduling works

Laravel has a built-in scheduler (`app/Console/Kernel.php`). One cron entry on the host runs `php artisan schedule:run` every minute. The framework decides which jobs to run based on declared cadence.

Each scheduled command **dispatches queued jobs** rather than doing work inline:

- The command itself runs in a few milliseconds
- The actual work happens on Horizon workers
- This keeps the scheduler from getting stuck and lets work parallelise

## Singleton runs

Many of these jobs must **never run twice in parallel** (e.g., counter flush would double-count). Laravel's `withoutOverlapping()` helper uses a Redis lock to ensure only one instance runs at a time.

## Where the scheduler runs in production

Two scenarios:

1. **VM-based deploy:** one VM has the cron entry; if that VM dies, the scheduler stops → bad
2. **Kubernetes deploy:** a `CronJob` resource runs the command; K8s ensures it runs even if a node fails → good

We pick option 2 in production. For local dev, just run a single container with the cron line.

## Reports — generated as queued jobs

Generating a daily PDF report touches many tables and may take 30+ seconds. Doing it inline in the scheduler would block.

The flow:

1. Scheduler dispatches `GenerateDailyReportJob`
2. Job runs on a separate worker pool (`reporting` queue)
3. Job produces a PDF (using `dompdf` or `wkhtmltopdf` via a Laravel package)
4. PDF is uploaded to S3
5. Job emails admin team with a presigned download URL (expires in 7 days)

Reports include:

- New signups (companies + applicants)
- Revenue (from Stripe)
- Top 10 active jobs by applications
- Plan distribution
- Email send / bounce stats
- System uptime

## Idempotency for sweepers

Sweepers may re-run if the worker crashed mid-execution. They must be **idempotent**:

- Marking a job `closed` when it's already `closed` is a no-op
- Sending a "subscription expiring in 7 days" email twice is bad — store a `last_reminder_sent_at` on the subscription and skip if already sent today

## What about the counter flush?

Job views and clicks are written to Redis (`INCR job:{id}:views`) for speed. A scheduled job every minute:

1. Reads Redis counters with `SCAN`
2. For each, increments the corresponding Postgres column
3. Resets the Redis counter to 0 (atomically: `GETDEL`)

This trades exactness (counter could lag by 60 seconds) for huge write performance.

## Failure modes

| Failure | Mitigation |
|---|---|
| Scheduler missed a run (worker died) | Sweepers are designed to "catch up" on the next run — they look at state, not events |
| Report job fails | Retry once, then alert admin via Slack |
| Email-sending job fails | Notification service handles retries |
| Counter flush fails | Counter accumulates more in Redis; next run flushes more — no data loss |

## What NOT to schedule

- **Anything user-facing-latency-sensitive.** A user clicking "Apply" should not wait for any scheduled job.
- **Anything event-driven.** If something should happen "when X happens", emit an event — don't poll for it on a schedule.

## Future: cron orchestration

If scheduled jobs grow beyond ~30 entries across services, consider a workflow engine like **Temporal** or **Apache Airflow** to orchestrate cross-service workflows. Until then, Laravel's scheduler + Kubernetes CronJobs is the right level.
