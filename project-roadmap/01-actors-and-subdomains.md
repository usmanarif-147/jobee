# 01 — Actors & Subdomains

## Three independent audiences, three subdomains

Each audience has its own UI app, its own login screen, and its own role model. The frontends are three separate apps; the backend is the 10-microservice system described in file `03-microservices-breakdown.md`.

| Subdomain | Audience | What they do |
|---|---|---|
| `admin.job-hunter.com` | Super admin team | Manage everything on the platform |
| `company.job-hunter.com/{company-uuid}` | Company users | Post jobs and manage applications |
| `job-hunter.com` | Public + applicants | Browse jobs and apply |

## Super Admin

- Login (separate auth realm — admin users live in their own table)
- View / add registered companies
- View any company's job posts
- Add Stripe plans (CRUD on subscription plans)
- Bulk email broadcasts to companies or applicants
- Send / receive scheduled platform reports (daily / weekly / monthly)
- Subscription expiry sweeper management
- Statistics overview page (total companies, active subs, MRR, top jobs, etc.)
- Add admin sub-users with roles & permissions
- Real-time chat with companies + share files

## Company

- Register / login (with email confirmation)
- Buy a subscription plan (gated capability — only subscribed companies can post jobs)
- CRUD job posts (with title, description, skill tags, deadline, applicant cap)
- See clicks, views, application count per job
- See applicant details + resumes
- Bulk-email applicants for interview / accept / reject (1 to 1000 at a time)
- Auto-resume-parsing on application (queued)
- Add company sub-users with roles & permissions
- Real-time chat with admin + with other subscribed companies + share files
- FCM push notifications when applications arrive (fan-out to multiple users with that role)
- Profile management

## Applicant / Public visitor

- Browse jobs without an account, with filters
- Register / login freely
- Save jobs to favourites
- Apply to jobs (upload resume; gated by applicant cap)
- See list of applied jobs and favourite jobs

## Why three subdomains, not three completely separate apps

- Shared backend services (one user table per role group, one job table) prevent data drift
- One codebase per frontend keeps roles cleanly isolated
- Subdomains give clean URL boundaries (cookies, CORS, branding)
- A single API gateway can route to one set of backend services regardless of which subdomain hit it

## Why subdomain (not path) for company

`company.job-hunter.com/{uuid}` — the UUID makes URLs unguessable and makes future per-company branding (custom domains, white-label) easy to bolt on.
