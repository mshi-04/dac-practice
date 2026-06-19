---
name: dac-practice
description: Work on the DacPractice Database as Code project. Use when changing AWS Aurora or DynamoDB design docs, Atlas migration guidance, AWS resource definitions, generated migrations, AI-facing project docs, or repository workflow documentation.
---

# DacPractice

この skill は、DacPractice リポジトリで Database as Code 関連の作業をするときに使う。

## 参照順

作業内容に応じて、必要な文書だけ読む。

- プロジェクト全体の前提: [../../../docs/project-context.md](../../../docs/project-context.md)
- DaC workflow: [../../../docs/database-as-code-workflow.md](../../../docs/database-as-code-workflow.md)
- AWS resource: [../../../docs/aws-resource-guidelines.md](../../../docs/aws-resource-guidelines.md)
- Aurora: [../../../docs/aurora-guidelines.md](../../../docs/aurora-guidelines.md)
- DynamoDB: [../../../docs/dynamodb-guidelines.md](../../../docs/dynamodb-guidelines.md)
- 変更レビュー: [../../../docs/change-review-guidelines.md](../../../docs/change-review-guidelines.md)

## 基本手順

1. `git status -sb` で branch と作業ツリーを確認する。
2. 変更対象が Aurora、DynamoDB、AWS resource、docs のどれかを分類する。
3. 変更対象に関係する `docs/` の文書を読む。
4. Aurora は relational schema migration、DynamoDB は access pattern と key design を中心に扱う。
5. AWS resource 定義を変更する場合は、採用した IaC tool の validate/plan/synth を実行する。
6. 生成物や migration は、適用前提・破壊的変更・rollback 不能性を確認する。
7. `git diff --check` を実行してから完了報告する。

## 検証

利用可能なものだけ実行し、実行できないものは理由を明記する。

```powershell
git diff --check
```

Atlas、Docker、IaC tool が使える環境では、変更内容に応じて検証 command を追加する。
