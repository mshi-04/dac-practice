# dac-practice

Database as Code practice project.

This repository is for practicing Database as Code with AWS database services.

The target databases are:

- Amazon Aurora
- Amazon DynamoDB

The project is currently in the documentation-first phase. AI-facing project
guidance lives under [docs/ai](docs/ai).

Aurora practice targets Amazon Aurora PostgreSQL-compatible Edition. The local
practice target uses PostgreSQL 16 with Atlas migrations.

## Requirements

- Git
- Docker, when using local database practice targets
- Atlas CLI, when practicing Aurora-style relational migrations locally
- An AWS IaC tool, to be selected later

## Read First

- [AGENTS.md](AGENTS.md)
- [docs/ai/project-context.md](docs/ai/project-context.md)
- [docs/ai/database-as-code-workflow.md](docs/ai/database-as-code-workflow.md)
- [docs/ai/aws-resource-guidelines.md](docs/ai/aws-resource-guidelines.md)
- [docs/ai/aurora-guidelines.md](docs/ai/aurora-guidelines.md)
- [docs/ai/dynamodb-guidelines.md](docs/ai/dynamodb-guidelines.md)
- [docs/ai/change-review-guidelines.md](docs/ai/change-review-guidelines.md)
- [docs/decisions/0001-aurora-postgresql-compatible.md](docs/decisions/0001-aurora-postgresql-compatible.md)

## Aurora Local Migration Practice

When Docker and Atlas are available, validate and apply the local Aurora
PostgreSQL-compatible migration practice with:

```powershell
docker compose up -d db
$env:DATABASE_URL = "postgres://app:app_password@localhost:5432/appdb?search_path=public&sslmode=disable"
atlas migrate validate --env local
atlas migrate apply --env local
```

`schema.sql` is the desired schema for local practice. `migrations/` contains
reviewable SQL migrations. `atlas.hcl` reads the target database URL from
`DATABASE_URL` so credentials are not stored in the Atlas configuration.

## Project Layout

```text
.
├── .agents/
│   └── skills/
├── atlas.hcl
├── docker-compose.yml
├── docs/
│   ├── decisions/
│   └── ai/
├── migrations/
└── schema.sql
```

`atlas.hcl`, `docker-compose.yml`, and `schema.sql` are early local practice
scaffolding. Revisit them when the Aurora engine and AWS IaC tool are selected.
