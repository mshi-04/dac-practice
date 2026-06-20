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
直接接続しません。Terraform state 用の S3 backend は `infra/terraform/bootstrap/` で先に作成します。

#### 1. State bucket の bootstrap

`infra/terraform/bootstrap/` は main stack の remote state を保存する S3 bucket を作成します。
versioning、server-side encryption、public access block を有効にし、非 TLS access を拒否します。
この stack は state bucket 自体を作るため local state を使い、backend block を持ちません。

```powershell
Set-Location infra/terraform/bootstrap
terraform init
terraform fmt -check
terraform validate
terraform plan -var "aws_region=<region>" -var "state_bucket_name=<globally-unique-bucket>"
terraform apply -var "aws_region=<region>" -var "state_bucket_name=<globally-unique-bucket>"
```

`backend.hcl` 自体は Git 管理しません。bootstrap で出力した bucket 名を `backend.hcl` に書き、
main Terraform を初期化します。

#### 2. Main stack の初期化と plan/apply

```powershell
Set-Location infra/terraform
Copy-Item backend.hcl.example backend.hcl
# backend.hcl の bucket に bootstrap で作成した bucket 名を設定する。
terraform init -backend-config=backend.hcl
terraform fmt -check
terraform validate
terraform plan -var "aws_region=<region>"
terraform apply -var "aws_region=<region>"
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

### 初回運用 runbook

検証環境を最初に立ち上げ、手動 deploy で公開済み tag を適用するまでの実行順です。

1. **State bootstrap**: `infra/terraform/bootstrap/` を apply し、state bucket を作成する。
2. **Terraform plan / apply**: bucket 名を `backend.hcl` に設定して main stack を init し、
   plan で差分を確認してから apply する。Aurora、VPC、NAT gateway、CodeBuild、OIDC role、
   Secrets Manager secret などが作成される。
3. **Atlas Registry read token の Secrets Manager 登録**: Terraform が作成した
   `atlas_registry_token_secret_arn` の secret に、Atlas Cloud の Registry read token を投入する。
   token 値は Git・workflow・Terraform code には残さない。
4. **GitHub Environment 設定**: `aurora-verification` Environment を作成し、必須項目を設定する。
   - 承認者（required reviewers）を最低 1 名設定する。
   - Environment variable `AWS_REGION`: 検証環境の region。
   - Environment variable `AWS_DEPLOY_ROLE_ARN`: Terraform 出力 `github_deploy_role_arn`。
   - Environment variable `CODEBUILD_PROJECT_NAME`: Terraform 出力 `codebuild_project_name`。
5. **手動 deploy**: `Deploy verification Aurora` workflow を `workflow_dispatch` で起動し、
   `migration_tag` に公開済みの immutable SHA tag を入力して、承認後に実行する。

#### 初回 deploy の成功確認

- **GitHub Actions**: `Deploy verification Aurora` の run が success で完了する。
- **CodeBuild CloudWatch Logs**: status → dry-run → apply → status の各コマンドが成功している。
- **Atlas migration status**: CodeBuild log の `migrate status` が pending migration なしを示す。
- **Aurora の migration revision table**: Aurora 上の Atlas revision table（`atlas_schema_revisions`）に
  適用済み version が記録されている。

#### 費用・破棄時の注意

- **Aurora Serverless v2**: 最小 ACU でも常時課金される。検証が不要な間は破棄を検討する。
- **NAT gateway**: 時間課金とデータ処理課金が発生する。private subnet の CodeBuild が
  Atlas Registry / image 取得に使うため、稼働中は維持コストがかかる。
- **backup retention**: Aurora の自動 backup は retention 期間中 storage 課金が続く。破棄時は
  保持された snapshot / backup を確認する。
- **KMS key**: Aurora 暗号化用の customer managed key は月額課金がある。`terraform destroy`
  では削除予約（waiting period）となり、即時削除されない。
- **deletion protection**: cluster は `deletion_protection = true`。破棄するには先に
  `-var "deletion_protection=false"` で apply してから destroy する。

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
