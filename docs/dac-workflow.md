# DaC Workflow

## 基本方針

このプロジェクトでは、DaC を次の 4 層に分けて扱う。

1. AWS resource definition: RDS PostgreSQL インスタンス、DynamoDB table、network、parameter、backup。
2. Relational schema migration: RDS PostgreSQL の table、index、constraint、view、function。
3. NoSQL data model definition: DynamoDB の access pattern、key design、secondary index。
4. Operational policy: encryption、backup、restore、retention、monitoring、cost guardrail。

これらは同じ PR に混ぜすぎない。影響範囲と reviewer の責務が追える単位に分ける。

## RDS PostgreSQL と DynamoDB の責務分離

- RDS PostgreSQL は relational consistency、transaction、SQL query、join、foreign key が必要な
  データに使う想定。
- DynamoDB は key-value / document access、predictable low-latency query、高い
  scale-out が必要なデータに使う想定。
- EC サイトでは、注文確定、在庫引当、決済状態更新の source of truth は RDS PostgreSQL に置き、
  カート、閲覧履歴、lookup cache は DynamoDB の access pattern として別に設計する。
- checkout workflow を変える場合は、PostgreSQL transaction 境界、DynamoDB 同期、失敗時の
  forward fix 方針を同じ PR で review できるようにする。
- どちらに置くか迷う場合は、先に access pattern、整合性要件、transaction 境界、
  query pattern、想定 scale、cost sensitivity を文書化する。

## 変更の流れ

1. 変更目的を書く。
2. 対象 DB を RDS PostgreSQL / DynamoDB / both に分類する。
3. access pattern または relational invariant を明確にする。
4. desired state を code として変更する。
5. migration または resource plan を生成する。
6. generated change を review する。
7. local で可能な検証を実行する。
8. 未検証の範囲を完了報告に残す。

## source of truth

- RDS PostgreSQL schema の source of truth は Atlas migration と schema 定義の組み合わせで扱う。
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
- Registry は migration directory の配布・確認用であり、RDS PostgreSQL への適用は別の
  deployment workflow で明示的に扱う。

## Atlas を使う RDS PostgreSQL lifecycle

Atlas の対象は RDS PostgreSQL の relational schema だけとする。DynamoDB の
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

`Deploy verification RDS` workflow は、自動経路（`Publish Atlas Registry` 成功後の
`workflow_run`）に加えて `workflow_dispatch` の手動経路を持つ。

- 用途: Terraform / GitHub Environment / Secrets の初回設定後に、既に Atlas Registry へ
  公開済みの immutable SHA tag を検証 RDS PostgreSQL へ適用・検証する。新しい migration は追加しない。
- 入力値: 必須 input `migration_tag` に、Atlas Registry へ公開済みの immutable commit SHA tag を
  渡す。受け付けるのは 40桁の小文字16進数のみで、空文字や形式違反は CodeBuild 起動前に失敗させる。
- 実行内容: 自動経路と同じく VPC 内 CodeBuild が同一 SHA tag を status、dry-run、apply、
  status の順に実行する。
- 重複実装の回避: migration tag の決定だけを event ごとに分岐し、手動実行時は input の
  `migration_tag`、自動実行時は `github.event.workflow_run.head_sha` を `MIGRATION_TAG` として
  CodeBuild に渡す。deployment 処理は共通とする。
- 自動経路の制約は維持する。`workflow_run` は成功した `Publish Atlas Registry`、`push` イベント、
  `develop` branch、同一リポジトリ由来だけを許可する。

## Terraform による検証 RDS PostgreSQL

`infra/terraform/` は verification 専用の VPC、private RDS PostgreSQL、Secrets Manager、
CodeBuild、GitHub OIDC role を管理する。CodeBuild だけが RDS PostgreSQL の port に接続できる。
private subnet の CodeBuild は Atlas Registry と container image を取得するため NAT gateway を経由する。

Terraform state backend は `infra/terraform/bootstrap/` で作成した暗号化 S3 bucket を使う。
bootstrap stack は versioning、customer managed KMS key による server-side encryption、public access block を有効にし、
非 TLS access を拒否する。state lock は S3 native locking（`use_lockfile=true`）で行い、`<key>.tflock` object を使う。
別途の DynamoDB lock table は持たない。
state bucket 自体を作るため local state を使い backend block を持たない。`backend.hcl` は Git に含めず、
`backend.hcl.example` をコピーして bootstrap で得た bucket 名を設定する。
検証環境を作る前に、Atlas Registry read token を Terraform が作成する Secrets Manager secret に登録する。

### Terraform plan の CI 検証

`Terraform Plan` workflow は `infra/terraform/` または workflow 自身の変更を含む内部 branch への
push で、`terraform fmt -check -recursive`、`terraform init -backend=false`、`terraform validate` を
実行する。AWS 読み取りが必要な `terraform plan` は、repository variables の `AWS_REGION` と
`AWS_TERRAFORM_PLAN_ROLE_ARN` が設定されている場合だけ実行する。fork PR には AWS credential を
渡さない。

`infra/terraform/plan/` は CI の plan 専用 root module であり、main stack の `s3` backend を
初期化しない。CI はこの module を local state で実行し、remote state の読取り、lock、apply は行わない。

`AWS_TERRAFORM_PLAN_ROLE_ARN` には Terraform output
`github_terraform_plan_role_arn` を設定する。この OIDC role は GitHub Environment
`terraform-plan` を通過した job だけを信頼し、plan に必要な AWS resource の read action に
限定する。Environment には required reviewers を設定する。CI は remote state を使わず、apply は
実行しない。
branch に対応する open PR がある場合は、plan の結果を PR コメントへ作成または更新する。

### 初回運用 runbook

検証環境の初回構築から手動 deploy までは次の順で実行する。詳細手順とコマンドは README の
「初回運用 runbook」を参照する。

1. State bootstrap: `infra/terraform/bootstrap/` を apply し、state 用 S3 bucket を作成する（lock は S3 native locking）。
2. Terraform plan / apply: bucket 名を `backend.hcl` に設定して main stack を init し、
   plan を確認してから apply する。
3. Atlas Registry read token の Secrets Manager 登録: Terraform が作成した secret に token を投入する。
   token 値は Git・workflow・Terraform code に残さない。
4. GitHub Environment 設定: `rds-verification` には `AWS_REGION`、
   `AWS_DEPLOY_ROLE_ARN`、`CODEBUILD_PROJECT_NAME` を設定する。`terraform-plan` にも required
   reviewers を設定し、repository variables には Terraform output
   `github_terraform_plan_role_arn` を `AWS_TERRAFORM_PLAN_ROLE_ARN` として、同じ region を
   `AWS_REGION` として設定する。
5. 手動 deploy: `Deploy verification RDS` を `workflow_dispatch` で起動し、公開済み SHA tag を
   入力して実行する。

初回 deploy の成功は、GitHub Actions の run 結果、CodeBuild の CloudWatch Logs、Atlas の
`migrate status`、RDS PostgreSQL の Atlas revision table（`atlas_schema_revisions`）で確認する。
RDS PostgreSQL、NAT gateway、backup retention、KMS key は稼働中・破棄時の費用に影響するため、
不要時は破棄を検討する。`deletion_protection` を有効にしているため、破棄前に無効化が必要になる。

## Migration file format

- `migrations/*.sql` と `migrations/atlas.sum` は `.gitattributes` で LF に固定する。
- Atlas の checksum は migration file のバイト列を比較するため、Windows の CRLF 変換を
  許可しない。

## Production CD

productionはverificationと同一AWSアカウント内に置くが、Terraform state、resource prefix、
VPC CIDR、RDS PostgreSQL/DynamoDB resources、CodeBuild、IAM roles、Secrets Manager secretsは分離する。
共有するGitHub OIDC providerは`infra/terraform/production/`がTerraform stateで管理する。
`infra/terraform/`のverification stackは同providerをdata sourceで参照するため、同一アカウント内に
OIDC providerを重複作成しない。production stackを先にbootstrapする。

### 開始条件と承認

- 本番CDは`Deploy production`だけであり、同一repositoryの`main` pushに対する`CI` workflowが成功した
  `workflow_run`だけを受け付ける。PR、fork、`develop`、CI失敗からは起動しない。
- 対象commitで`infra/terraform/production/`が変わるとTerraform planを、`migrations/`または`atlas.hcl`が
  変わるとAtlas validate/lintを実行する。両方が変わる場合も同一runに含める。
- plan jobはGitHub Environment `production-plan`を使用し、read-only OIDC roleでremote stateを読む。
  applyとRDS PostgreSQL migrationはGitHub Environment `production`を共有し、required reviewersによる一回の承認後に
  同じCI-tested commitを順に処理する。
- `production-plan`と`production`のdeployment branch rulesは、保護済みの`main`だけを許可する。
  `production`にはrequired reviewersを設定し、Environmentを指定する任意workflowへの権限委譲を防ぐ。

### 単一CD pipeline

`Deploy production`は次の順で実行する。

1. Terraformのformat/validateと、保存可能なbinary planを作る。plan summaryには、承認者が作成・更新・削除と
   課金影響を確認すべきことを明示する。
2. migrationがある場合は、承認前に`atlas migrate validate`と`atlas migrate lint`を再実行する。lintが失敗すると
   `production` Environmentのjobは開始しない。
3. `production` Environmentの承認後、同一commitの保存済みbinary planを`infra/terraform/production/`全体へapplyする。
   DynamoDBだけを対象にした`-target` applyはstate整合性を壊すため使用しない。
4. migrationがある場合は、その同じcommit SHAをimmutable Atlas Registry tagとして公開し、VPC内CodeBuildへ渡す。
   CodeBuildはRDS PostgreSQL migrationを適用する。

binary planの保持期間は7日で、期限切れ時は対象runを再実行して新しいplanを作る。stateが変更されてplanが古くなった
場合はapplyを失敗させ、新しいCI成功commitから計画を作り直す。

### 費用確認

Terraform planがRDS PostgreSQL、NAT gateway、Elastic IP、KMS key、CloudWatch Logs、backup retentionなどの
費用に影響するresourceの作成・変更を示す場合、承認者は`production` Environmentを承認する前に、対象と
課金要因を確認する。CDの設定・検証作業中にAWSへ`apply`を実行してresourceを作成してはならない。

production stateのbackendはS3 object `dac-practice/production/terraform.tfstate`を使い、lockはS3 native locking
（`use_lockfile=true`、`<key>.tflock` object）で行う。`infra/terraform/bootstrap/`を別のproduction用bucket名と
`project_name=dac-practice-production`で管理者が一度だけapplyし、bucket名をGitHub Environment variableに登録する。production stackはCD roleを使う前に
管理者権限で一度applyし、OIDC rolesとCodeBuildを作成する。以後の変更はCD roleだけで行う。

### IAM / OIDC要件

GitHub OIDC trust policyはすべて`token.actions.githubusercontent.com:aud`を`sts.amazonaws.com`に固定する。
subjectはEnvironment単位で固定し、branch wildcardやrepository全体の信頼は許可しない。

- production plan role: `repo:mshi-04/DacPractice:environment:production-plan` のみを信頼する。
  production Terraform resourcesのdescribe/list、state objectの`GetObject`、state bucketのprefix限定`ListBucket`だけを許可する。
- production Terraform apply role: `repo:mshi-04/DacPractice:environment:production` のみを信頼する。
  production prefixのTerraform管理対象と、production state objectのread/write、`<key>.tflock` objectのlock操作だけを許可する。
  sessionは最大2時間とし、RDS PostgreSQLを伴うTerraform applyが15分を超えてもAWS credentialが失効しないようにする。
  `iam:PassRole`はproduction CodeBuild service roleへの`codebuild.amazonaws.com`向けpassに限定し、
  `secretsmanager:GetSecretValue`は許可しない。
- production RDS PostgreSQL deploy role: 同じ`production` subjectだけを信頼し、production CodeBuild projectの
  `codebuild:StartBuild`と`codebuild:BatchGetBuilds`だけを許可する。sessionは最大1時間とし、
  CodeBuildの30分timeoutとworkflowの最大40分pollingをカバーする。
- CodeBuild role: production RDS PostgreSQLのRDS管理secretとAtlas Registry read token secretに限り
  `secretsmanager:GetSecretValue`を許可する。GitHub Actionsのrole、workflow variable、artifact、logへ
  database credentialやRegistry read tokenを渡さない。

GitHub Environment `production-plan`には`AWS_REGION`、`TF_STATE_BUCKET`、`TF_STATE_KEY`、
`TF_VPC_CIDR`、`ATLAS_REGISTRY`、`AWS_TERRAFORM_PRODUCTION_PLAN_ROLE_ARN`を設定する。
`production`には同じbackend/VPC/Registry variablesに加え、`AWS_TERRAFORM_PRODUCTION_APPLY_ROLE_ARN`、
`AWS_PRODUCTION_RDS_DEPLOY_ROLE_ARN`、`PRODUCTION_CODEBUILD_PROJECT_NAME`を設定する。
role ARNとproject nameはproduction Terraform outputsから登録する。Atlasのpublish/lintには既存の
GitHub Actions Secret `ATLAS_TOKEN`（Atlas Cloud organization Bot token）を使い、CodeBuildが読む
Registry read tokenはAWS Secrets Managerだけに保存する。

`ATLAS_REGISTRY`はTerraformの`atlas_registry`入力と、GitHub Actionsがimmutable tagを公開するRegistry名を
一致させるための唯一の設定値である。default値に依存せず、両Environmentへ同じ値を明示して登録する。

### RDS PostgreSQL production apply

単一CDの承認後、GitHub ActionsはRDS PostgreSQLへ直接接続せず、immutable Registry SHAをCodeBuildへ渡す。CodeBuildは
`set +x`のままSecrets Managerからusername/passwordだけを取得し、Terraformから注入したRDS endpoint・port・
database nameと組み合わせる。validate、status、dry-run、`atlas migrate apply --tx-mode all`、statusの順に実行する。

`--tx-mode all`によりpending migration全体を単一transactionとして扱う。non-transactional DDLを含むmigrationは
適用を失敗させる。失敗時に自動rollbackや既存migrationの書換えは行わず、確認後に新しいforward migrationを作成する。

production CodeBuild用のprivate subnetは、Atlas Registryとcontainer image取得専用の単一NAT gatewayを経由する。
これはapplication traffic用の経路ではないため、costを優先して単一AZとする。可用性要件が変わる場合はAZごとのNAT gatewayへ
変更し、NAT gatewayの時間・転送料金を改めてreviewする。

RDS PostgreSQL の automated backup retentionは`db_backup_retention_period`で明示する。現在のAWS Free Tier制約に
合わせたdefaultは1日であり、account planをアップグレードしたproduction運用では、復旧要件に応じて7日以上へ
引き上げてreviewする。

### 初回workflow起動の確認

`workflow_run`を使う`Deploy production`は、workflow定義がdefault branch（`main`）に存在してから起動する。
初回の`main`マージ後、次のproduction Terraformまたはmigration変更で、`CI`成功から単一の`Deploy production` runが
作られることをActions画面で確認する。runが作られない場合は、workflow名、default branch、`workflow_run`の
source branch条件を確認してから本番変更を続ける。

## 採用 tool の考え方

- RDS PostgreSQL の SQL schema migration には Atlas を使う。
- RDS PostgreSQL インスタンスや DynamoDB table など AWS resource は `infra/` の Terraform で定義する。
- DynamoDB は SQL migration ではなく、table/index/access pattern の変更として review する。

## 公式 reference

- Amazon RDS for PostgreSQL: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html
- RDS Blue/Green Deployments: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments.html
- DynamoDB best practices: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html
- DynamoDB data modeling: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/data-modeling.html
- CloudFormation DynamoDB table reference: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-dynamodb-table.html
