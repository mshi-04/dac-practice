# dac-practice

AWS database management のための Database as Code プロジェクトです。

**日本語** | [English](README.en.md)

正本は日本語版です。英語版は日本語版に追随します。

> **このプロジェクトは 2026-08-02 に開発を終了しました。**
> 以降の機能追加と保守は行いません。repository は Database as Code の設計・検証・運用方針の
> 記録として参照専用で残します。CI/CD workflow と AWS 環境は稼働を前提としないため、
> 以下の手順をそのまま実行しても動作しない場合があります。

database schema、AWS database resource design、review guidance を code として管理します。

対象 database:

- Amazon RDS for PostgreSQL
- Amazon DynamoDB

基盤整備フェーズで開発を終了しました。運用方針と AI 向けの判断基準は [docs](docs) に置いています。

練習用 domain は EC サイトを想定しています。RDS PostgreSQL schema と DynamoDB access pattern の
分担は [docs/ecommerce-data-model.md](docs/ecommerce-data-model.md) を参照してください。
checkout の transaction 境界は [docs/ecommerce-checkout.md](docs/ecommerce-checkout.md) に置いています。
その境界を実際に動く PL/pgSQL として実装したものは [sql/](sql/README.md) にあります。
DynamoDB の ShoppingCart、CustomerActivity、OrderLookup は
`infra/terraform/dynamodb.tf` で定義しています。設計の詳細は上記 data model を参照してください。

Amazon RDS for PostgreSQL 16 を対象にします。
local validation では PostgreSQL 16 と Atlas migration を使います。

## 必要なもの

- Git
- Docker: local database validation を使う場合
- Atlas CLI: RDS PostgreSQL style の relational migration を local で検証する場合
- Terraform: AWS resource 定義を検証する場合

## 最初に読む

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

## RDS PostgreSQL Local Validation

Docker と Atlas が使える場合は、local の RDS PostgreSQL migration を
次のコマンドで検証・適用します。

```powershell
docker compose up -d db
$env:DATABASE_URL = "postgres://app:app_password@localhost:5432/appdb?search_path=public&sslmode=disable"
atlas migrate validate --env local
atlas migrate apply --env local
```

`schema.sql` は local validation 用の desired schema です。`migrations/` には
review 可能な SQL migration を置きます。`atlas.hcl` は target database URL を
`DATABASE_URL` から読むため、credential を Atlas 設定に保存しません。

schema を変更するときは、`schema.sql` を先に更新し、Atlas で migration を生成します。
共有環境に適用済みの migration は編集せず、修正は新しい forward migration で行います。

```powershell
atlas migrate diff --env local "change_description"
atlas migrate lint --env local --latest 1
$latestVersion = (Get-ChildItem migrations/*.sql | Sort-Object Name | Select-Object -Last 1).BaseName.Split('_')[0]
(Get-Content -Raw migrate.test.hcl).Replace('__LATEST_MIGRATION__', $latestVersion) | Set-Content "$env:TEMP/migrate.test.hcl"
atlas migrate test --env local "$env:TEMP/migrate.test.hcl"
atlas migrate validate --env local
```

## Local Seed Data

`seeds/ecommerce_local_seed.sql` は、ローカル PostgreSQL で商品検索、在庫確認、
checkout を試すためのデータです。`customers`、`product_categories`、`products`、
`inventory_items` に、active / draft / archived の商品と引当済み在庫を含むサンプルを投入します。
Atlas migration ではなくローカル検証専用の SQL のため、shared environment には適用しません。

各テーブルの自然キー（email / slug / SKU / product_id）で UPSERT するため、seed は繰り返し
実行できます。再実行時は、対象レコードの値と在庫数が seed 定義の値に戻ります。

```powershell
# schema を適用済みにする
docker compose up -d db
$env:DATABASE_URL = "postgres://app:app_password@localhost:5432/appdb?search_path=public&sslmode=disable"
atlas migrate apply --env local

# psql が host にある場合
$pg = "postgres://app:app_password@localhost:5432/appdb?sslmode=disable"
psql $pg -v ON_ERROR_STOP=1 -f seeds/ecommerce_local_seed.sql
```

checkout と全ての代表 query を試す場合は、関数を登録してから検証用クエリを実行します。
`seeds/verify_representative_queries.sql` は checkout、配送 event、在庫更新を transaction 内で
生成して、最後に `ROLLBACK` します。永続化されるのは seed データだけです。

```powershell
$pg = "postgres://app:app_password@localhost:5432/appdb?sslmode=disable"
Get-ChildItem sql/functions/*.sql | Sort-Object Name | ForEach-Object {
  psql $pg -v ON_ERROR_STOP=1 -f $_.FullName
}
psql $pg -v ON_ERROR_STOP=1 -f seeds/verify_representative_queries.sql
```

host に `psql` がない場合は、repo をコンテナへコピーして実行します。

```powershell
docker compose cp seeds db:/tmp/seeds
docker compose cp sql/functions db:/tmp/functions
docker compose exec -T db sh -c 'for file in /tmp/functions/*.sql; do psql -v ON_ERROR_STOP=1 -U app -d appdb -f "$file"; done'
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U app -d appdb -f /tmp/seeds/ecommerce_local_seed.sql
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U app -d appdb -f /tmp/seeds/verify_representative_queries.sql
```

検証クエリは [docs/ecommerce-data-model.md の PostgreSQL の代表 query](docs/ecommerce-data-model.md#postgresql-の代表-query)
を対象にしています。checkout の成功・在庫不足・取消・出荷の連続デモは
[sql/README.md](sql/README.md) の `sql/examples/` を使用してください。

## CI

GitHub Actions は、PR 検証と Atlas Registry 公開を分けて実行します。

- `CI`: `main` / `develop` 向け PR で migration の検証と local PostgreSQL への適用を行う。
- `Atlas Migration Lint`: migration 変更を含む同一リポジトリ PR で Atlas の lint を実行し、結果を PR にコメントする。
- `Publish Atlas Registry`: `develop` の `migrations/` または `atlas.hcl` の変更後に、
  migration directory を Atlas Registry の `dacpractice` へ公開する。
- `Terraform Plan`: `infra/terraform/` の内部 branch push で Terraform の format / validate を実行し、
  OIDC plan role 設定後は `terraform plan` も実行する。設定は
  [docs/dac-workflow.md#terraform-plan-の-ci-検証](docs/dac-workflow.md#terraform-plan-の-ci-検証) を参照する。
- `Deploy production`: `main` へのpushで `CI` が成功した場合だけ起動する唯一の本番CD。
  Terraform plan、Atlas validate/lint、GitHub Environment承認、Terraform apply、Atlas Registry公開、
  RDS PostgreSQL migration applyを同一runで順に実行する。`develop`、PR、CI失敗、fork由来のworkflowからは
  本番のOIDC credentialを取得しない。

Registry 公開には、Atlas Cloud の Bot token を GitHub Actions Secret の `ATLAS_TOKEN` として
登録する必要があります。Bot は Atlas Cloud の organization settings で作成します。詳細は
[docs/dac-workflow.md#atlas-registry-公開](docs/dac-workflow.md#atlas-registry-公開) と
[docs/change-review-guidelines.md#ci-の扱い](docs/change-review-guidelines.md#ci-の扱い) を参照してください。

## Production CD

`infra/terraform/production/` はverificationとは別のTerraform state、VPC、RDS PostgreSQL、DynamoDB、
CodeBuild、IAM rolesを管理します。これらとPostgreSQL schema migrationは、`Deploy production`の単一CDで
同じCI成功commitからデプロイします。GitHub OIDC providerはproduction stackが一度だけ管理し、
verification stackは同providerをdata sourceで参照します。

- **Terraform**: 対象commitでTerraform変更がある場合、read-only roleでplanを作成します。承認者はplanの
  resource変更と課金影響を確認し、GitHub Environment `production`のrequired reviewersが承認した後、
  別のapply roleで保存済みbinary planを適用します。stateが変わってplanが古くなった場合、applyは失敗します。
- **RDS PostgreSQL / Atlas**: migration変更がある場合、同じrunでlintとchecksum validationを完了してから承認を待ちます。
  承認後に対象commitをimmutable Registry SHA tagとして公開し、private subnetのCodeBuildがSecrets Managerから
  接続情報を取得してapplyします。GitHub-hosted runnerはRDS PostgreSQLへ接続しません。
- **原子性**: CodeBuildは `atlas migrate apply --tx-mode all` を使用します。pending migration全体を
  一つのtransactionで実行するため、non-transactional DDLを含むリリースは失敗します。失敗時は
  自動rollbackではなく、新しいforward migrationで修正します。

初回bootstrap、GitHub Environment variables、OIDC roleの最小権限は
[docs/dac-workflow.md#production-cd](docs/dac-workflow.md#production-cd) を参照してください。

## Verification RDS PostgreSQL Deployment

`infra/terraform/` は RDS PostgreSQL（`db.t4g.micro`）と、VPC 内で Atlas を
実行する CodeBuild を定義します。RDS は private subnet に置き、GitHub-hosted runner から
直接接続しません。Terraform state 用の S3 backend は `infra/terraform/bootstrap/` で先に作成します。

### 1. State bucket の bootstrap

`infra/terraform/bootstrap/` は main stack の remote state を保存する S3 bucket を作成します。
state lock は S3 native locking（`use_lockfile=true`、`<key>.tflock` object）で行うため、別途の
DynamoDB lock table は作成しません。S3 bucket は versioning、server-side encryption、
public access block を有効にし、非 TLS access を拒否します。
この stack は state bucket 自体を作るため local state を使い、backend block を持ちません。

```powershell
Set-Location infra/terraform/bootstrap
terraform init
terraform fmt -check
terraform validate
terraform plan -var "aws_region=<region>" -var "state_bucket_name=<globally-unique-bucket>"
terraform apply -var "aws_region=<region>" -var "state_bucket_name=<globally-unique-bucket>"
```

`backend.hcl` 自体は Git 管理しません。bootstrap で出力した bucket 名を
`backend.hcl` に書き、main Terraform を初期化します。

### 2. Main stack の初期化と plan/apply

```powershell
Set-Location infra/terraform
Copy-Item backend.hcl.example backend.hcl
# backend.hcl の bucket に bootstrap の出力値を設定する（lock は use_lockfile=true）。
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -var "aws_region=<region>"
terraform apply -var "aws_region=<region>"
```

`develop` の migration 変更は SHA tag 付きで Atlas Registry に公開されます。続く
`Deploy verification RDS` workflow は GitHub Environment `rds-verification` を使用して、
OIDC 経由で CodeBuild を起動し、その tag のみを dry-run・apply・status の順に実行します。
必要な GitHub Environment variables は `AWS_REGION`、`AWS_DEPLOY_ROLE_ARN`、
`CODEBUILD_PROJECT_NAME` です。

### 手動再デプロイ

Terraform / GitHub Environment / Secrets の初回設定後に、既に Atlas Registry へ公開済みの
immutable SHA tag を検証 RDS PostgreSQL へ再適用したい場合は、`Deploy verification RDS` workflow を
`workflow_dispatch`（手動実行）で起動します。新しい migration は追加しません。

- 用途: 初回セットアップ直後の動作確認や、公開済み tag の検証 RDS PostgreSQL への再適用。
- 入力値 `migration_tag`: Atlas Registry に公開済みの immutable commit SHA tag。
  40桁の小文字16進数のみを受け付けます。空文字や形式違反は CodeBuild 起動前に失敗します。
- 実行内容: CodeBuild が同一 tag を status・dry-run・apply・status の順に実行します。
- 実行手順: GitHub の Actions タブで `Deploy verification RDS` を開き、`Run workflow` から
  `migration_tag` に対象の SHA tag を入力して実行します。

自動経路（`Publish Atlas Registry` 成功後の `workflow_run`）と手動経路は、migration tag の
決定だけを event ごとに分岐し、CodeBuild への適用処理は共通です。GitHub-hosted runner から
RDS PostgreSQL へ直接接続しません。

### 初回運用 runbook

検証環境を最初に立ち上げ、手動 deploy で公開済み tag を適用するまでの実行順です。

1. **State bootstrap**: `infra/terraform/bootstrap/` を apply し、state bucket を作成する（lock は S3 native locking）。
2. **Terraform plan / apply**: bucket 名を `backend.hcl` に設定して main stack を init し、
   plan で差分を確認してから apply する。RDS PostgreSQL、VPC、NAT gateway、CodeBuild、OIDC role、
   Secrets Manager secret などが作成される。
3. **Atlas Registry read token の Secrets Manager 登録**: Terraform が作成した
   `atlas_registry_token_secret_arn` の secret に、Atlas Cloud の Registry read token を投入する。
   token 値は Git・workflow・Terraform code には残さない。
4. **GitHub Environment 設定**: `rds-verification` Environment を作成し、必須項目を設定する。
   - Environment variable `AWS_REGION`: 検証環境の region。
   - Environment variable `AWS_DEPLOY_ROLE_ARN`: Terraform 出力 `github_deploy_role_arn`。
   - Environment variable `CODEBUILD_PROJECT_NAME`: Terraform 出力 `codebuild_project_name`。
   - `terraform-plan` Environment にも required reviewers を設定する。Terraform plan の AWS 読取り
     OIDC role は、この Environment を通過した job だけが利用できる。
5. **手動 deploy**: `Deploy verification RDS` workflow を `workflow_dispatch` で起動し、
   `migration_tag` に公開済みの immutable SHA tag を入力して実行する。

#### 初回 deploy の成功確認

- **GitHub Actions**: `Deploy verification RDS` の run が success で完了する。
- **CodeBuild CloudWatch Logs**: status → dry-run → apply → status の各コマンドが成功している。
- **Atlas migration status**: CodeBuild log の `migrate status` が pending migration なしを示す。
- **RDS の migration revision table**: RDS PostgreSQL 上の Atlas revision table（`atlas_schema_revisions`）に
  適用済み version が記録されている。

#### 費用・破棄時の注意

- **RDS PostgreSQL**: `db.t4g.micro`・20GB gp2・Single-AZ の課金はアカウント区分で変わる。
  2025-07-15 より前に free tier を有効化したアカウントは、作成から 12 か月間 750 時間/月と
  20GB storage が無料。それ以降に作成したアカウントは Free / Paid plan の対象で、通常料金が
  付与クレジットから消費される。いずれの場合も、検証が不要な間は破棄してアイドル課金を避ける。
- **NAT gateway**: 時間課金とデータ処理課金が発生する。private subnet の CodeBuild が
  Atlas Registry / image 取得に使うため、稼働中は維持コストがかかる。
- **backup retention**: RDS の自動 backup は retention 期間中 storage 課金が続く。破棄時は
  保持された snapshot / backup を確認する。
- **KMS key**: RDS 暗号化用の customer managed key は月額課金がある。`terraform destroy`
  では削除予約（waiting period）となり、即時削除されない。
- **RDS PostgreSQL logs**: CloudWatch Logs への export は 30 日で保持する。変更時は
  `postgres_log_retention_in_days` を明示し、調査・監査要件と費用を review する。
- **deletion protection**: verification は `deletion_protection = true`。破棄するには先に
  `-var "deletion_protection=false"` で apply してから destroy する（production は default false）。

## 構成

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

## Checkout SQL の実装

`sql/` に、`docs/ecommerce-checkout.md` の checkout 境界を RDS PostgreSQL
（PG16）の PL/pgSQL 関数として実装しています。schema は変更せず、既存テーブルの上で動く
再利用可能な関数とデモを置いています。

- `sql/functions/checkout_place_order.sql`: 販売状態・価格・在庫の再確認、oversell しない
  単一 `UPDATE` での在庫引当、注文/明細/住所 snapshot 作成、決済記録を 1 トランザクションで行う。
- `sql/functions/inventory_release_order.sql`: 注文取消時の在庫戻し。
- `sql/functions/inventory_consume_order.sql`: 出荷時の在庫消費。
- `sql/functions/inventory_adjust.sql`: 入庫・棚卸・手動調整。
- `sql/examples/`: サンプルデータと、checkout 成功 → 在庫不足で失敗 → 取消 → 出荷を
  通すデモ（`demo_checkout.sql`）。

登録とデモの実行手順は [sql/README.md](sql/README.md) を参照してください。

`atlas.hcl`、`docker-compose.yml`、`schema.sql` は local validation のための
scaffolding です。AWS IaC tool を選定したタイミングで見直します。
