# AWS Resource Guidelines

## 目的

RDS PostgreSQL インスタンス、DynamoDB table、network、security、backup などの AWS resource を
Database as Code の一部として扱う。

schema や migration だけでなく、database を安全に動かすための resource 設定も
code review の対象にする。

## IaC tool

IaC tool は Terraform を採用する。AWS CDK や CloudFormation とは混在させない。
Terraform code は `infra/` に置く。

- state 管理: state は安全な backend に保存し、secret を含めない。
- 環境分離: 環境ごとに workspace または directory と state を分け、命名と tag を一貫させる。
- 検証 command: `terraform fmt -check`、`terraform validate`、`terraform plan` を使う。
- secret 管理: secret、password、token は code・state・repository に置かず、変数や secret manager で扱う。
- drift detection: `terraform plan` の差分で drift を検知し、code に反映するか戻す。

GitHub Actions は OIDC role で CodeBuild の起動と結果取得だけを許可する。RDS PostgreSQL への
network 接続と Atlas apply は private subnet 内の CodeBuild role が実行する。

## resource design

- 環境ごとに resource 名、tag、state を分離する。
- secret、password、token を repository に置かない。
- IAM は最小権限を基本にする。
- encryption、backup、deletion protection、retention は明示的に設定する。
- public network exposure は必要性を説明できる場合だけ許可する。
- cost に影響する capacity、instance class、replica、storage、backup retention を review する。

## RDS PostgreSQL resource

RDS PostgreSQL では、少なくとも次を code review 対象にする。

- engine family と version
- cluster / instance topology
- subnet group
- security group
- parameter group
- backup retention
- deletion protection
- encryption
- log export
- CloudWatch Logs の retention
- secret management

## DynamoDB resource

DynamoDB では、少なくとも次を code review 対象にする。

- billing mode
- partition key / sort key
- GSI / LSI
- point-in-time recovery
- deletion protection
- encryption
- TTL
- Streams
- resource policy
- tags
- partition key の cardinality と hot partition のリスク
- item size と 400 KB の item size 上限

## drift

AWS console で直接変更された内容は drift として扱う。

drift を見つけた場合は、次のどちらかで解消する。

- 意図した変更として IaC code に反映する。
- 意図しない変更として AWS resource を code の desired state に戻す。
