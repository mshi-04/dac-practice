# DaC Workflow

## 基本方針

このプロジェクトでは、DaC を次の 4 層に分けて扱う。

1. AWS resource definition: Aurora cluster、DynamoDB table、network、parameter、backup。
2. Relational schema migration: Aurora の table、index、constraint、view、function。
3. NoSQL data model definition: DynamoDB の access pattern、key design、secondary index。
4. Operational policy: encryption、backup、restore、retention、monitoring、cost guardrail。

これらは同じ PR に混ぜすぎない。影響範囲と reviewer の責務が追える単位に分ける。

## Aurora と DynamoDB の責務分離

- Aurora は relational consistency、transaction、SQL query、join、foreign key が必要な
  データに使う想定。
- DynamoDB は key-value / document access、predictable low-latency query、高い
  scale-out が必要なデータに使う想定。
- EC サイトでは、注文確定、在庫引当、決済状態更新の source of truth は Aurora に置き、
  カート、閲覧履歴、lookup cache は DynamoDB の access pattern として別に設計する。
- checkout workflow を変える場合は、Aurora transaction 境界、DynamoDB 同期、失敗時の
  forward fix 方針を同じ PR で review できるようにする。
- どちらに置くか迷う場合は、先に access pattern、整合性要件、transaction 境界、
  query pattern、想定 scale、cost sensitivity を文書化する。

## 変更の流れ

1. 変更目的を書く。
2. 対象 DB を Aurora / DynamoDB / both に分類する。
3. access pattern または relational invariant を明確にする。
4. desired state を code として変更する。
5. migration または resource plan を生成する。
6. generated change を review する。
7. local で可能な検証を実行する。
8. 未検証の範囲を完了報告に残す。

## source of truth

- Aurora schema の source of truth は Atlas migration と schema 定義の組み合わせで扱う。
- DynamoDB の source of truth は table/index 定義と access pattern 文書で扱う。
- AWS resource の source of truth は Terraform の code と state で扱う。
- AWS console での手動変更は drift として扱い、code に反映するか戻す。

## Atlas Registry 公開

- PR では migration の検証だけを行い、Atlas Registry は更新しない。
- `develop` にマージされ、`migrations/` または `atlas.hcl` が変わったときだけ
  `Publish Atlas Registry` workflow が `dacpractice` を更新する。
- workflow は GitHub Actions Secret の `ATLAS_TOKEN` に保存した Atlas Cloud の Bot token を使う。
  Bot は organization settings で作成し、token は repository や workflow 定義に保存しない。
- 同時実行を直列化し、先に開始した公開処理を途中で取り消さない。
- Registry は migration directory の配布・確認用であり、Aurora への適用は別の
  deployment workflow で明示的に扱う。

## Atlas を使う Aurora lifecycle

Atlas の対象は Aurora PostgreSQL-compatible の relational schema だけとする。DynamoDB の
table や access pattern は Atlas の対象外であり、別の resource 定義と設計文書で扱う。

1. `schema.sql` を desired state として変更する。
2. `atlas migrate diff --env local <name>` で versioned migration を生成する。
3. PR CI で checksum、schema validate、lint、最新 version を対象とする migration test、空の PostgreSQL への apply、
   applied schema と desired state の diff を確認する。
4. `develop` マージ後に migration directory を `dacpractice:<commit-sha>` として Atlas Registry に公開する。
5. GitHub Environment の承認後、VPC 内 CodeBuild が Registry の同一 SHA tag を status、dry-run、apply、status の順に実行する。

Registry の publish token と、CodeBuild が読む Registry token は分離する。DB 接続情報と
Registry read token は AWS Secrets Manager に保存し、GitHub Actions には保存しない。

### 公開済み tag の手動再デプロイ

`Deploy verification Aurora` workflow は、自動経路（`Publish Atlas Registry` 成功後の
`workflow_run`）に加えて `workflow_dispatch` の手動経路を持つ。

- 用途: Terraform / GitHub Environment / Secrets の初回設定後に、既に Atlas Registry へ
  公開済みの immutable SHA tag を検証 Aurora へ適用・検証する。新しい migration は追加しない。
- 入力値: 必須 input `migration_tag` に、Atlas Registry へ公開済みの immutable commit SHA tag を
  渡す。受け付けるのは 40桁の小文字16進数のみで、空文字や形式違反は CodeBuild 起動前に失敗させる。
- 承認: 手動経路も GitHub Environment `aurora-verification` の承認を必ず通す。
- 実行内容: 承認後、自動経路と同じく VPC 内 CodeBuild が同一 SHA tag を status、dry-run、apply、
  status の順に実行する。
- 重複実装の回避: migration tag の決定だけを event ごとに分岐し、手動実行時は input の
  `migration_tag`、自動実行時は `github.event.workflow_run.head_sha` を `MIGRATION_TAG` として
  CodeBuild に渡す。deployment 処理は共通とする。
- 自動経路の制約は維持する。`workflow_run` は成功した `Publish Atlas Registry`、`push` イベント、
  `develop` branch、同一リポジトリ由来だけを許可する。

## Terraform による検証 Aurora

`infra/terraform/` は verification 専用の VPC、private Aurora Serverless v2、Secrets Manager、
CodeBuild、GitHub OIDC role を管理する。CodeBuild だけが Aurora の PostgreSQL port に接続できる。
private subnet の CodeBuild は Atlas Registry と container image を取得するため NAT gateway を経由する。

Terraform state backend は `infra/terraform/bootstrap/` で作成した暗号化 S3 bucket を使う。
bootstrap stack は versioning、server-side encryption、public access block を有効にし、
非 TLS access を拒否する。state bucket 自体を作るため local state を使い backend block を持たない。
`backend.hcl` は Git に含めず、`backend.hcl.example` をコピーして bootstrap で得た bucket 名を設定する。
検証環境を作る前に、Atlas Registry read token を Terraform が作成する Secrets Manager secret に登録する。

### Terraform plan の CI 検証

`Terraform Plan` workflow は `infra/terraform/` または workflow 自身の変更を含む内部 branch への
push で、`terraform fmt -check -recursive`、`terraform init -backend=false`、`terraform validate` を
実行する。AWS 読み取りが必要な `terraform plan` は、repository variables の `AWS_REGION` と
`AWS_TERRAFORM_PLAN_ROLE_ARN` が設定されている場合だけ実行する。fork PR には AWS credential を
渡さない。

`AWS_TERRAFORM_PLAN_ROLE_ARN` には Terraform output
`github_terraform_plan_role_arn` を設定する。この OIDC role は branch push だけを信頼し、plan に
必要な AWS resource の read action に限定する。CI は remote state を使わず、apply は実行しない。

### 初回運用 runbook

検証環境の初回構築から手動 deploy までは次の順で実行する。詳細手順とコマンドは README の
「初回運用 runbook」を参照する。

1. State bootstrap: `infra/terraform/bootstrap/` を apply し、state 用 S3 bucket を作成する。
2. Terraform plan / apply: bucket 名を `backend.hcl` に設定して main stack を init し、
   plan を確認してから apply する。
3. Atlas Registry read token の Secrets Manager 登録: Terraform が作成した secret に token を投入する。
   token 値は Git・workflow・Terraform code に残さない。
4. GitHub Environment `aurora-verification` 設定: 承認者、`AWS_REGION`、`AWS_DEPLOY_ROLE_ARN`、
   `CODEBUILD_PROJECT_NAME` を設定する。repository variables には、Terraform output
   `github_terraform_plan_role_arn` を `AWS_TERRAFORM_PLAN_ROLE_ARN` として、同じ region を
   `AWS_REGION` として設定する。
5. 手動 deploy: `Deploy verification Aurora` を `workflow_dispatch` で起動し、公開済み SHA tag を
   入力して承認後に実行する。

初回 deploy の成功は、GitHub Actions の run 結果、CodeBuild の CloudWatch Logs、Atlas の
`migrate status`、Aurora の Atlas revision table（`atlas_schema_revisions`）で確認する。
Aurora Serverless v2、NAT gateway、backup retention、KMS key は稼働中・破棄時の費用に影響するため、
不要時は破棄を検討する。`deletion_protection` を有効にしているため、破棄前に無効化が必要になる。

## Migration file format

- `migrations/*.sql` と `migrations/atlas.sum` は `.gitattributes` で LF に固定する。
- Atlas の checksum は migration file のバイト列を比較するため、Windows の CRLF 変換を
  許可しない。

## 採用 tool の考え方

- Aurora の SQL schema migration には Atlas を使う。
- Aurora cluster や DynamoDB table など AWS resource は `infra/` の Terraform で定義する。
- DynamoDB は SQL migration ではなく、table/index/access pattern の変更として review する。

## 公式 reference

- Aurora best practices: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html
- Aurora blue/green deployment best practices: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments-best-practices.html
- DynamoDB best practices: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html
- DynamoDB data modeling: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/data-modeling.html
- CloudFormation DynamoDB table reference: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-dynamodb-table.html
