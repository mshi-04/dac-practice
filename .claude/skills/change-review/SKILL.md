---
name: change-review
description: Review Database as Code changes. Use when reviewing Aurora migrations, DynamoDB changes, or Terraform resource definitions for data loss, capacity or cost, backup, security, and reviewability.
---

# Change Review

Aurora migration、DynamoDB 変更、Terraform resource 定義の review をするときに使う。

## 参照

判断基準の詳細は docs を読む（この skill には複製しない）。

- review 観点の詳細: [change-review-guidelines](../../../docs/change-review-guidelines.md)

## 手順

1. 変更対象が Aurora / DynamoDB / Terraform resource / docs のどれかを分類する。
2. desired state と実際に適用される差分が review できるか確認する。
3. data loss、lock、長時間実行、既存 data との不整合がないか確認する。
4. capacity、cost、backup、restore、encryption、network exposure への影響を確認する。
5. docs の方針と実際の変更がずれていないか確認する。

## 完了条件

```powershell
git status -sb
git diff --check
```

変更領域に応じて [aurora-migration](../aurora-migration/SKILL.md) / [dynamodb-modeling](../dynamodb-modeling/SKILL.md) /
[aws-resource](../aws-resource/SKILL.md) の検証 command を実行する。使えない command は理由を完了報告に明記する。
