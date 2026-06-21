---
name: dynamodb-modeling
description: DynamoDB table and access pattern design. Use when designing or changing DynamoDB tables, partition or sort keys, GSI or LSI, capacity, TTL, or access patterns.
---

# DynamoDB Modeling

DynamoDB の table 設計・access pattern・key design・capacity を扱うときに使う。

## 参照

判断基準の詳細は docs を読む（この skill には複製しない）。

- DynamoDB 設計方針: [dynamodb-guidelines](../../../docs/dynamodb-guidelines.md)
- Aurora との責務分離: [dac-workflow](../../../docs/dac-workflow.md)

## 手順

1. access pattern を先に列挙する。
2. access pattern に合わせて partition key / sort key を設計する（hot partition を避ける）。
3. 必要な access pattern にだけ GSI / LSI を足し、projection を最小化する。
4. on-demand か provisioned か、PITR・backup・TTL・Streams の要否を決める。TTL を使う場合は attribute の書込みと cache miss 時の Aurora 再生成を併せて設計する。
5. access pattern と key design の対応表を残す。
6. 設計変更で table replacement や index recreation が必要か確認する。

## 注意

- LSI は table 作成時しか追加できないので設計時に確定させる。
- capacity 変更は cost への影響を見積もる。
- 実際の table 定義は `infra/` の Terraform 側で行う（[aws-resource](../aws-resource/SKILL.md)）。

## 完了条件

`git diff --check` と Terraform の format / validate を実行し、access pattern と
[dynamodb-guidelines](../../../docs/dynamodb-guidelines.md) の整合を確認する。実行できない検証は理由を報告する。
