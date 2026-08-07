# dac-practice

A Database as Code project for AWS database management.

[日本語](README.md) | **English**

The Japanese [README.md](README.md) is the canonical version; this English README follows it.

> **Development of this project ended on 2026-08-02.**
> No further features or maintenance are planned. The repository is kept read-only as a record of
> the Database as Code design, validation, and operations policies. The CI/CD workflows and the AWS
> environment are not assumed to be running, so the procedures below may not work as written.

Database schema, AWS database resource design, and review guidance are all managed as code.

Target databases:

- Amazon RDS for PostgreSQL
- Amazon DynamoDB

Development ended during the foundation phase. Operational policies and the decision criteria
written for AI agents live in [docs](docs) (Japanese).

The practice domain is an e-commerce site. The split between the RDS PostgreSQL schema and the
DynamoDB access patterns is described in [docs/ecommerce-data-model.md](docs/ecommerce-data-model.md).
Checkout transaction boundaries are described in [docs/ecommerce-checkout.md](docs/ecommerce-checkout.md),
and those boundaries are implemented as runnable PL/pgSQL under [sql/](sql/README.md).
The DynamoDB tables `ShoppingCart`, `CustomerActivity`, and `OrderLookup` are defined in
`infra/terraform/dynamodb.tf`; see the data model document above for the design details.

Amazon RDS for PostgreSQL 16 is the target engine. Local validation uses PostgreSQL 16 and
Atlas migrations.

## Requirements

- Git
- Docker: to run local database validation
- Atlas CLI: to validate RDS PostgreSQL-style relational migrations locally
- Terraform: to validate AWS resource definitions

## Read first

- [AGENTS.md](AGENTS.md)
- [docs/project-context.md](docs/project-context.md)
- [docs/dac-workflow.md](docs/dac-workflow.md)
- [docs/aws-resource-guidelines.md](docs/aws-resource-guidelines.md)
- [docs/rds-postgres-guidelines.md](docs/rds-postgres-guidelines.md)
- [docs/dynamodb-guidelines.md](docs/dynamodb-guidelines.md)
- [docs/ecommerce-data-model.md](docs/ecommerce-data-model.md)
- [docs/ecommerce-checkout.md](docs/ecommerce-checkout.md)
- [docs/ecommerce-consistency-recovery.md](docs/ecommerce-consistency-recovery.md)
- [docs/change-review-guidelines.md](docs/change-review-guidelines.md)

## RDS PostgreSQL local validation

With Docker and Atlas available, validate and apply the local RDS PostgreSQL migrations with:

```powershell
docker compose up -d db
$env:DATABASE_URL = "postgres://app:app_password@localhost:5432/appdb?search_path=public&sslmode=disable"
atlas migrate validate --env local
atlas migrate apply --env local
```

`schema.sql` is the desired schema used for local validation, and `migrations/` holds the
reviewable SQL migrations. `atlas.hcl` reads the target database URL from `DATABASE_URL`, so no
credential is stored in the Atlas configuration.

To change the schema, update `schema.sql` first and generate a migration with Atlas. Migrations
already applied to a shared environment are never edited; corrections go into a new forward
migration.

```powershell
atlas migrate diff --env local "change_description"
atlas migrate lint --env local --latest 1
$latestVersion = (Get-ChildItem migrations/*.sql | Sort-Object Name | Select-Object -Last 1).BaseName.Split('_')[0]
(Get-Content -Raw migrate.test.hcl).Replace('__LATEST_MIGRATION__', $latestVersion) | Set-Content "$env:TEMP/migrate.test.hcl"
atlas migrate test --env local "$env:TEMP/migrate.test.hcl"
atlas migrate validate --env local
```

## Local seed data

`seeds/ecommerce_local_seed.sql` provides the data needed to try product search, inventory checks,
and checkout on a local PostgreSQL. It loads samples into `customers`, `product_categories`,
`products`, and `inventory_items`, including active / draft / archived products and reserved
inventory. It is local-validation-only SQL rather than an Atlas migration, so it is never applied
to a shared environment.

Each table is upserted by its natural key (email / slug / SKU / product_id), so the seed is
repeatable. On re-run, the target records and inventory counts return to the values defined in the
seed.

```powershell
# make sure the schema is applied
docker compose up -d db
$env:DATABASE_URL = "postgres://app:app_password@localhost:5432/appdb?search_path=public&sslmode=disable"
atlas migrate apply --env local

# when psql is available on the host
$pg = "postgres://app:app_password@localhost:5432/appdb?sslmode=disable"
psql $pg -v ON_ERROR_STOP=1 -f seeds/ecommerce_local_seed.sql
```

To exercise checkout and every representative query, register the functions first and then run the
verification queries. `seeds/verify_representative_queries.sql` creates checkout, shipping events,
and inventory updates inside a transaction and ends with `ROLLBACK`, so only the seed data is
persisted.

```powershell
$pg = "postgres://app:app_password@localhost:5432/appdb?sslmode=disable"
Get-ChildItem sql/functions/*.sql | Sort-Object Name | ForEach-Object {
  psql $pg -v ON_ERROR_STOP=1 -f $_.FullName
}
psql $pg -v ON_ERROR_STOP=1 -f seeds/verify_representative_queries.sql
```

When `psql` is not installed on the host, copy the repository into the container and run it there.

```powershell
docker compose cp seeds db:/tmp/seeds
docker compose cp sql/functions db:/tmp/functions
docker compose exec -T db sh -c 'for file in /tmp/functions/*.sql; do psql -v ON_ERROR_STOP=1 -U app -d appdb -f "$file"; done'
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U app -d appdb -f /tmp/seeds/ecommerce_local_seed.sql
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U app -d appdb -f /tmp/seeds/verify_representative_queries.sql
```

The verification queries target
[the representative PostgreSQL queries in docs/ecommerce-data-model.md](docs/ecommerce-data-model.md#postgresql-の代表-query).
For the sequential demo of checkout success, insufficient inventory, cancellation, and shipment,
use `sql/examples/` as described in [sql/README.md](sql/README.md).

## CI

GitHub Actions separates PR validation from Atlas Registry publishing.

- `CI`: validates migrations on PRs targeting `main` / `develop` and applies them to a local PostgreSQL.
- `Atlas Migration Lint`: runs Atlas lint on same-repository PRs that touch migrations and comments the result on the PR.
- `Publish Atlas Registry`: publishes the migration directory to the Atlas Registry project `dacpractice`
  after `migrations/` or `atlas.hcl` changes on `develop`.
- `Terraform Plan`: runs Terraform format / validate on internal branch pushes under `infra/terraform/`,
  and also runs `terraform plan` once the OIDC plan role is configured. See
  [docs/dac-workflow.md#terraform-plan-の-ci-検証](docs/dac-workflow.md#terraform-plan-の-ci-検証).
- `Deploy production`: the only production CD. It starts on a push to `main` and only when `CI` succeeded.
  A single run performs Terraform plan, Atlas validate/lint, GitHub Environment approval, Terraform apply,
  Atlas Registry publishing, and the RDS PostgreSQL migration apply in order. Production OIDC credentials
  are never issued to `develop`, PRs, failed CI runs, or fork-originated workflows.

Registry publishing requires an Atlas Cloud bot token registered as the GitHub Actions secret
`ATLAS_TOKEN`. The bot is created in the Atlas Cloud organization settings. See
[docs/dac-workflow.md#atlas-registry-公開](docs/dac-workflow.md#atlas-registry-公開) and
[docs/change-review-guidelines.md#ci-の扱い](docs/change-review-guidelines.md#ci-の扱い) for details.

## Production CD

`infra/terraform/production/` manages a Terraform state, VPC, RDS PostgreSQL, DynamoDB, CodeBuild,
and IAM roles that are separate from the verification stack. Those resources and the PostgreSQL
schema migrations are deployed from the same CI-passing commit by the single `Deploy production` CD.
The GitHub OIDC provider is owned by the production stack alone; the verification stack references
the same provider through a data source.

- **Terraform**: when the target commit contains Terraform changes, a plan is produced with a read-only
  role. The approver reviews the resource changes and the cost impact, and after the required reviewers
  of the GitHub Environment `production` approve, a separate apply role applies the saved binary plan.
  If the state moved and the plan is stale, the apply fails.
- **RDS PostgreSQL / Atlas**: when the commit contains migration changes, lint and checksum validation
  complete in the same run before approval is requested. After approval the commit is published as an
  immutable Registry SHA tag, and CodeBuild in a private subnet fetches the connection information from
  Secrets Manager and applies it. GitHub-hosted runners never connect to RDS PostgreSQL.
- **Atomicity**: CodeBuild uses `atlas migrate apply --tx-mode all`. All pending migrations run in one
  transaction, so a release containing non-transactional DDL fails. Failures are corrected with a new
  forward migration rather than an automatic rollback.

For the initial bootstrap, the GitHub Environment variables, and the least-privilege OIDC roles, see
[docs/dac-workflow.md#production-cd](docs/dac-workflow.md#production-cd).

## Verification RDS PostgreSQL deployment

`infra/terraform/` defines an RDS PostgreSQL instance (`db.t4g.micro`) and a CodeBuild project that
runs Atlas inside the VPC. RDS lives in a private subnet and is not reachable directly from
GitHub-hosted runners. The S3 backend for the Terraform state is created first in
`infra/terraform/bootstrap/`.

### 1. Bootstrap the state bucket

`infra/terraform/bootstrap/` creates the S3 bucket that stores the main stack's remote state. State
locking uses S3 native locking (`use_lockfile=true` with a `<key>.tflock` object), so no separate
DynamoDB lock table is created. The bucket enables versioning, server-side encryption, and public
access block, and denies non-TLS access. Because this stack creates the state bucket itself, it uses
local state and has no backend block.

```powershell
Set-Location infra/terraform/bootstrap
terraform init
terraform fmt -check
terraform validate
terraform plan -var "aws_region=<region>" -var "state_bucket_name=<globally-unique-bucket>"
terraform apply -var "aws_region=<region>" -var "state_bucket_name=<globally-unique-bucket>"
```

`backend.hcl` itself is not tracked in Git. Put the bucket name produced by the bootstrap stack into
`backend.hcl` and initialize the main Terraform stack.

### 2. Initialize and plan/apply the main stack

```powershell
Set-Location infra/terraform
Copy-Item backend.hcl.example backend.hcl
# Set the bootstrap output as the bucket in backend.hcl (locking uses use_lockfile=true).
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -var "aws_region=<region>"
terraform apply -var "aws_region=<region>"
```

Migration changes on `develop` are published to the Atlas Registry with a SHA tag. The following
`Deploy verification RDS` workflow uses the GitHub Environment `rds-verification` to start CodeBuild
through OIDC and runs dry-run, apply, and status against that tag only. The required GitHub
Environment variables are `AWS_REGION`, `AWS_DEPLOY_ROLE_ARN`, and `CODEBUILD_PROJECT_NAME`.

### Manual redeployment

After the initial Terraform / GitHub Environment / Secrets setup, an already published immutable SHA
tag can be re-applied to the verification RDS PostgreSQL by starting the `Deploy verification RDS`
workflow via `workflow_dispatch`. No new migration is added.

- Purpose: smoke-testing right after the initial setup, or re-applying a published tag to the verification RDS PostgreSQL.
- Input `migration_tag`: an immutable commit SHA tag already published to the Atlas Registry.
  Only 40 lowercase hexadecimal characters are accepted; an empty or malformed value fails before CodeBuild starts.
- What runs: CodeBuild executes status, dry-run, apply, and status against the same tag, in that order.
- How to run: open `Deploy verification RDS` in the GitHub Actions tab, choose `Run workflow`, and enter the target SHA tag as `migration_tag`.

The automatic path (`workflow_run` after `Publish Atlas Registry` succeeds) and the manual path differ
only in how the migration tag is determined; the CodeBuild apply logic is shared. GitHub-hosted runners
never connect to RDS PostgreSQL directly.

### First-run runbook

The order of operations to bring up the verification environment and apply a published tag manually:

1. **State bootstrap**: apply `infra/terraform/bootstrap/` to create the state bucket (locking uses S3 native locking).
2. **Terraform plan / apply**: set the bucket name in `backend.hcl`, init the main stack, review the diff
   with plan, then apply. This creates RDS PostgreSQL, the VPC, the NAT gateway, CodeBuild, the OIDC role,
   the Secrets Manager secret, and so on.
3. **Register the Atlas Registry read token in Secrets Manager**: put the Atlas Cloud Registry read token
   into the secret exposed as `atlas_registry_token_secret_arn` by Terraform. The token value stays out of
   Git, workflows, and Terraform code.
4. **Configure the GitHub Environment**: create the `rds-verification` environment and set the required items.
   - Environment variable `AWS_REGION`: the region of the verification environment.
   - Environment variable `AWS_DEPLOY_ROLE_ARN`: the Terraform output `github_deploy_role_arn`.
   - Environment variable `CODEBUILD_PROJECT_NAME`: the Terraform output `codebuild_project_name`.
   - Also set required reviewers on the `terraform-plan` environment. The AWS read-only OIDC role for
     Terraform plan is only available to jobs that pass through that environment.
5. **Manual deploy**: start the `Deploy verification RDS` workflow via `workflow_dispatch` with a published
   immutable SHA tag as `migration_tag`.

#### Verifying the first deploy

- **GitHub Actions**: the `Deploy verification RDS` run completes successfully.
- **CodeBuild CloudWatch Logs**: status → dry-run → apply → status each succeed.
- **Atlas migration status**: `migrate status` in the CodeBuild log reports no pending migrations.
- **RDS migration revision table**: the Atlas revision table (`atlas_schema_revisions`) on RDS PostgreSQL
  records the applied versions.

#### Cost and teardown notes

- **RDS PostgreSQL**: how `db.t4g.micro` with 20GB gp2 and Single-AZ is billed depends on the AWS
  account. Accounts that had the free tier enabled before 2025-07-15 get 750 hours/month plus 20GB of
  storage free for 12 months from sign-up. Accounts created on or after that date fall under the
  Free / Paid plan, where usage is charged at the normal rate and covered by the granted credits until
  they run out. Either way, destroy it while it is not needed to avoid idle charges.
- **NAT gateway**: billed per hour and per processed byte. It stays a running cost because CodeBuild in the
  private subnet uses it to reach the Atlas Registry and pull images.
- **Backup retention**: automated RDS backups keep incurring storage charges during the retention period.
  Check the retained snapshots and backups when tearing down.
- **KMS key**: the customer managed key used for RDS encryption has a monthly charge. `terraform destroy`
  schedules deletion after a waiting period rather than deleting it immediately.
- **RDS PostgreSQL logs**: exports to CloudWatch Logs are retained for 30 days. When changing this, set
  `postgres_log_retention_in_days` explicitly and review the investigation / audit requirements against cost.
- **Deletion protection**: verification sets `deletion_protection = true`. To tear it down, apply with
  `-var "deletion_protection=false"` first, then destroy (production defaults to false).

## Layout

```text
.
├── .github/
│   └── workflows/
├── .agents/
│   └── skills/
├── .claude/
│   └── skills/
├── .codex/
│   └── skills/
├── atlas.hcl
├── docker-compose.yml
├── docs/
├── infra/
│   └── terraform/
├── migrations/
├── seeds/
├── schema.sql
├── sql/
└── tests/
```

## Checkout SQL implementation

`sql/` implements the checkout boundaries from `docs/ecommerce-checkout.md` as PL/pgSQL functions for
RDS PostgreSQL (PG16). The schema is unchanged; these are reusable functions and demos that run on top
of the existing tables.

- `sql/functions/checkout_place_order.sql`: re-checks sale status, price, and inventory, reserves stock
  with a single `UPDATE` that cannot oversell, creates the order / line items / address snapshot, and
  records the payment — all in one transaction.
- `sql/functions/inventory_release_order.sql`: returns stock when an order is cancelled.
- `sql/functions/inventory_consume_order.sql`: consumes stock on shipment.
- `sql/functions/inventory_adjust.sql`: receiving, stocktaking, and manual adjustments.
- `sql/examples/`: sample data and a demo (`demo_checkout.sql`) that walks through checkout success →
  failure on insufficient inventory → cancellation → shipment.

See [sql/README.md](sql/README.md) for how to register the functions and run the demo.

`atlas.hcl`, `docker-compose.yml`, and `schema.sql` are scaffolding for local validation. They will be
revisited once the AWS IaC tooling is settled.
