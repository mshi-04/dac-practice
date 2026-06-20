---
name: aws-resource
description: AWS resource definition with Terraform. Use when defining or changing Aurora clusters, DynamoDB tables, network, parameter groups, or backup as Terraform code under infra/.
---

# AWS Resource (Terraform)

Aurora cluster、DynamoDB table、network、parameter、backup などの AWS resource を
`infra/` の Terraform で定義するときに使う。

## 参照

判断基準の詳細は docs を読む（この skill には複製しない）。

- AWS resource 方針: [aws-resource-guidelines](../../../docs/aws-resource-guidelines.md)
- review 観点: [change-review-guidelines](../../../docs/change-review-guidelines.md)

## 手順

1. `infra/` に環境ごとに分けて Terraform code を置く（命名・tag を一貫させる）。
2. IAM は最小権限、encryption / backup / deletion protection / retention を明示する。
3. secret・password・token は code・state に書かず、変数や secret manager で扱う。
4. `terraform fmt -check` で整形を確認する。
5. `terraform validate` で構文・整合を確認する。
6. `terraform plan` で適用前の差分を review する。

## 注意

- IaC tool は Terraform に統一し、CDK / CloudFormation と混在させない。
- AWS console での手動変更は drift として扱い、code に反映するか戻す。
