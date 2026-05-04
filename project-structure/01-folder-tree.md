# 01 — Folder Tree

Visual layout only. No code, no descriptions. One git repo (monorepo).

## 1. Workspace top level

```
job-hunter/
├── services/
│   ├── identity-service/
│   ├── companies-service/
│   ├── jobs-service/
│   ├── payment-service/
│   ├── notification-service/
│   ├── chat-service/
│   ├── media-service/
│   ├── resume-parser-service/
│   ├── search-service/
│   └── reporting-service/
├── frontends/
│   ├── public-web/
│   ├── company-web/
│   └── admin-web/
├── infra/
├── event-schemas/
├── docs/
├── scripts/
├── .github/
│   └── workflows/
├── docker-compose.yml
├── Makefile
└── README.md
```

## 2. Inside a Laravel service

Applies to: `identity-service`, `companies-service`, `jobs-service`, `payment-service`, `notification-service`, `chat-service`, `media-service`, `search-service`, `reporting-service`.

```
identity-service/
├── app/
│   ├── Console/
│   │   └── Commands/
│   ├── Events/
│   ├── Http/
│   │   ├── Controllers/
│   │   ├── Middleware/
│   │   └── Requests/
│   ├── Jobs/
│   ├── Listeners/
│   ├── Models/
│   ├── Policies/
│   └── Services/
├── bootstrap/
├── config/
├── database/
│   ├── factories/
│   ├── migrations/
│   └── seeders/
├── docker/
├── public/
├── resources/
├── routes/
├── storage/
├── tests/
│   ├── Feature/
│   └── Unit/
├── Dockerfile
└── composer.json
```

## 3. Inside the Python service

```
resume-parser-service/
├── app/
│   ├── api/
│   ├── consumers/
│   ├── parsers/
│   └── schemas/
├── docker/
├── tests/
├── Dockerfile
└── pyproject.toml
```

## 4. Inside a frontend

Applies to: `public-web`, `company-web`, `admin-web`.

```
public-web/
├── assets/
├── components/
├── composables/
├── layouts/
├── middleware/
├── pages/
├── plugins/
├── public/
├── stores/
├── tests/
├── Dockerfile
├── nuxt.config.ts
└── package.json
```

## 5. Inside `infra/`

```
infra/
├── docker-compose/
├── helm/
│   ├── identity-service/
│   ├── companies-service/
│   ├── jobs-service/
│   ├── payment-service/
│   ├── notification-service/
│   ├── chat-service/
│   ├── media-service/
│   ├── resume-parser-service/
│   ├── search-service/
│   └── reporting-service/
├── k8s/
│   ├── argocd/
│   ├── kafka/
│   ├── monitoring/
│   └── secrets/
├── kong/
└── terraform/
    ├── aws/
    ├── environments/
    │   ├── production/
    │   └── staging/
    └── modules/
```

## 6. Inside `event-schemas/`

```
event-schemas/
├── chat/
├── companies/
├── identity/
├── jobs/
├── media/
├── notifications/
├── payments/
├── resume/
└── search/
```

