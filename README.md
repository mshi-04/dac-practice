# dac-practice

AWS database management のための Database as Code プロジェクトです。

database schema、AWS database resource design、review guidance を code として管理します。

対象 database:

- Amazon Aurora
- Amazon DynamoDB

現在は基盤整備フェーズです。運用方針と AI 向けの判断基準は [docs](docs) に置いています。

練習用 domain は EC サイトを想定しています。Aurora schema と DynamoDB access pattern の
分担は [docs/ecommerce-data-model.md](docs/ecommerce-data-model.md) を参照してください。
checkout の transaction 境界は [docs/ecommerce-checkout-workflow.md](docs/ecommerce-checkout-workflow.md) に置いています。

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
- [docs/database-as-code-workflow.md](docs/database-as-code-workflow.md)
- [docs/aws-resource-guidelines.md](docs/aws-resource-guidelines.md)
- [docs/aurora-guidelines.md](docs/aurora-guidelines.md)
- [docs/dynamodb-guidelines.md](docs/dynamodb-guidelines.md)
- [docs/ecommerce-data-model.md](docs/ecommerce-data-model.md)
- [docs/ecommerce-checkout-workflow.md](docs/ecommerce-checkout-workflow.md)
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

## CI

GitHub Actions は、PR 検証と Atlas Registry 公開を分けて実行します。

- `CI`: PR と `main` / `develop` への push で migration の検証と local PostgreSQL への適用を行う。
- `Publish Atlas Registry`: `develop` の `migrations/` または `atlas.hcl` の変更後に、
  migration directory を Atlas Registry の `dacpractice` へ公開する。

Registry 公開には、Atlas Cloud の Bot token を GitHub Actions Secret の `ATLAS_TOKEN` として
登録する必要があります。Bot は Atlas Cloud の organization settings で作成します。詳細は
[docs/database-as-code-workflow.md#atlas-registry-公開](docs/database-as-code-workflow.md#atlas-registry-公開) と
[docs/change-review-guidelines.md#ci-の扱い](docs/change-review-guidelines.md#ci-の扱い) を参照してください。

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
