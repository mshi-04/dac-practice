# dac-practice

Database as Code practice project.

This repository is for practicing Database as Code with AWS database services.

The target databases are:

- Amazon Aurora
- Amazon DynamoDB

The project is currently in the documentation-first phase. AI-facing project
guidance lives under [docs/ai](docs/ai).

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

## Project Layout

```text
.
├── .agents/
│   └── skills/
├── atlas.hcl
├── docker-compose.yml
├── docs/
│   └── ai/
├── migrations/
└── schema.sql
```

`atlas.hcl`, `docker-compose.yml`, and `schema.sql` are early local practice
scaffolding. Revisit them when the Aurora engine and AWS IaC tool are selected.
