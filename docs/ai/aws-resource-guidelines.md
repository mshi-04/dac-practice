# AWS Resource Guidelines

## 目的

Aurora cluster、DynamoDB table、network、security、backup などの AWS resource を
Database as Code の一部として扱う。

schema や migration だけでなく、database を安全に動かすための resource 設定も
code review の対象にする。

## IaC tool

Terraform、AWS CDK、CloudFormation のどれを使うかは後続で選定する。

選定までは、tool 固有の directory 構成や state backend を固定しない。選定 PR では次を
文書化する。

- 採用 tool
- state 管理方法
- 環境分離の方法
- plan / diff / deploy command
- secret 管理方針
- drift detection 方針

## resource design

- 環境ごとに resource 名、tag、state を分離する。
- secret、password、token を repository に置かない。
- IAM は最小権限を基本にする。
- encryption、backup、deletion protection、retention は明示的に設定する。
- public network exposure は必要性を説明できる場合だけ許可する。
- cost に影響する capacity、instance class、replica、storage、backup retention を review する。

## Aurora resource

Aurora では、少なくとも次を code review 対象にする。

- engine family と version
- cluster / instance topology
- subnet group
- security group
- parameter group
- backup retention
- deletion protection
- encryption
- log export
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

## drift

AWS console で直接変更された内容は drift として扱う。

drift を見つけた場合は、次のどちらかで解消する。

- 意図した変更として IaC code に反映する。
- 意図しない変更として AWS resource を code の desired state に戻す。
