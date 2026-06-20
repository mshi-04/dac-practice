# dac-practice

AWS database management のための Database as Code プロジェクトです。

database schema、AWS database resource design、review guidance を code として管理します。

対象 database:

- Amazon Aurora
- Amazon DynamoDB

現在は基盤整備フェーズです。運用方針と AI 向けの判断基準は [docs](docs) に置いています。

練習用 domain は EC サイトを想定しています。Aurora schema と DynamoDB access pattern の
分担は [docs/ecommerce-data-model.md](docs/ecommerce-data-model.md) を参照してください。
checkout の transaction 境界は [docs/ecommerce-checkout.md](docs/ecommerce-checkout.md) に置いています。

Aurora は Amazon Aurora PostgreSQL-compatible Edition を対象にします。
local validation では PostgreSQL 16 と Atlas migration を使います。

## 必要なもの

- Git
- Docker: local database validation を使う場合
- Atlas CLI: Aurora style の relational migration を local で検証する場合
- AWS IaC tool: 後続で選定

## 最初に読む

- [AGENTS.md](AGENTS.md)
- [docs/project-context.md](docs/project-context.md)
- [docs/dac-workflow.md](docs/dac-workflow.md)
- [docs/aws-resource-guidelines.md](docs/aws-resource-guidelines.md)
- [docs/aurora-guidelines.md](docs/aurora-guidelines.md)
- [docs/dynamodb-guidelines.md](docs/dynamodb-guidelines.md)
- [docs/ecommerce-data-model.md](docs/ecommerce-data-model.md)
- [docs/ecommerce-checkout.md](docs/ecommerce-checkout.md)
- [docs/change-review-guidelines.md](docs/change-review-guidelines.md)

## Aurora Local Validation

Docker と Atlas が使える場合は、local の Aurora PostgreSQL-compatible migration を
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
latestVersion = (Get-ChildItem migrations/*.sql | Sort-Object Name | Select-Object -Last 1).BaseName.Split('_')[0]
(Get-Content -Raw migrate.test.hcl).Replace('__LATEST_MIGRATION__', $latestVersion) | Set-Content "$env:TEMP/migrate.test.hcl"
atlas migrate test --env local "$env:TEMP/migrate.test.hcl"
atlas migrate validate --env local
```

## CI

GitHub Actions は、PR 検証と Atlas Registry 公開を分けて実行します。

- `CI`: `main` / `develop` 向け PR で migration の検証と local PostgreSQL への適用を行う。
- `Atlas Migration Lint`: migration 変更を含む同一リポジトリ PR で Atlas の lint を実行し、結果を PR にコメントする。
- `Publish Atlas Registry`: `develop` の `migrations/` または `atlas.hcl` の変更後に、
  migration directory を Atlas Registry の `dacpractice` へ公開する。

Registry 公開には、Atlas Cloud の Bot token を GitHub Actions Secret の `ATLAS_TOKEN` として
登録する必要があります。Bot は Atlas Cloud の organization settings で作成します。詳細は
[docs/dac-workflow.md#atlas-registry-公開](docs/dac-workflow.md#atlas-registry-公開) と
[docs/change-review-guidelines.md#ci-の扱い](docs/change-review-guidelines.md#ci-の扱い) を参照してください。

## Verification Aurora Deployment

`infra/terraform/` は Aurora PostgreSQL-compatible Serverless v2 と、VPC 内で Atlas を
実行する CodeBuild を定義します。Aurora は private subnet に置き、GitHub-hosted runner から
直接接続しません。Terraform state 用の S3 backend は bootstrap 済みであることが前提です。

```powershell
Set-Location infra/terraform
Copy-Item backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -var "aws_region=<region>"
```

`develop` の migration 変更は SHA tag 付きで Atlas Registry に公開されます。続く
`Deploy verification Aurora` workflow は GitHub Environment `aurora-verification` の承認後、
OIDC 経由で CodeBuild を起動し、その tag のみを dry-run・apply・status の順に実行します。
必要な GitHub Environment variables は `AWS_REGION`、`AWS_DEPLOY_ROLE_ARN`、
`CODEBUILD_PROJECT_NAME` です。

### 手動再デプロイ

Terraform / GitHub Environment / Secrets の初回設定後に、既に Atlas Registry へ公開済みの
immutable SHA tag を検証 Aurora へ再適用したい場合は、`Deploy verification Aurora` workflow を
`workflow_dispatch`（手動実行）で起動します。新しい migration は追加しません。

- 用途: 初回セットアップ直後の動作確認や、公開済み tag の検証 Aurora への再適用。
- 入力値 `migration_tag`: Atlas Registry に公開済みの immutable commit SHA tag。
  40桁の小文字16進数のみを受け付けます。空文字や形式違反は CodeBuild 起動前に失敗します。
- 承認: GitHub Environment `aurora-verification` の承認を必ず通過します。承認後に CodeBuild が
  同一 tag を status・dry-run・apply・status の順に実行します。
- 実行手順: GitHub の Actions タブで `Deploy verification Aurora` を開き、`Run workflow` から
  `migration_tag` に対象の SHA tag を入力して実行し、Environment の承認を行います。

自動経路（`Publish Atlas Registry` 成功後の `workflow_run`）と手動経路は、migration tag の
決定だけを event ごとに分岐し、CodeBuild への適用処理は共通です。GitHub-hosted runner から
Aurora へ直接接続しません。

## 構成

```text
.
├── .github/
│   └── workflows/
├── .agents/
│   └── skills/
├── atlas.hcl
├── docker-compose.yml
├── docs/
├── migrations/
└── schema.sql
```

`atlas.hcl`、`docker-compose.yml`、`schema.sql` は local validation のための
scaffolding です。AWS IaC tool を選定したタイミングで見直します。
