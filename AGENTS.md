# AGENTS.md

## プロジェクト

このリポジトリは、AWS の Aurora と DynamoDB を想定して Database as Code を学ぶための
プロジェクトです。

変更前に必要な範囲で以下を読むこと。

- [docs/ai/project-context.md](docs/ai/project-context.md)
- [docs/ai/database-as-code-workflow.md](docs/ai/database-as-code-workflow.md)
- [docs/ai/aws-resource-guidelines.md](docs/ai/aws-resource-guidelines.md)
- [docs/ai/aurora-guidelines.md](docs/ai/aurora-guidelines.md)
- [docs/ai/dynamodb-guidelines.md](docs/ai/dynamodb-guidelines.md)
- [docs/ai/change-review-guidelines.md](docs/ai/change-review-guidelines.md)

## 作業ルール

- `AGENTS.md` は薄く保ち、詳細な判断基準は `docs/ai/` に置く。
- Database as Code の学習体験が分かりやすくなる変更を優先する。
- Aurora の schema migration と DynamoDB の table/access pattern 設計を分けて扱う。
- AWS resource 定義、schema 定義、migration、運用 policy を code review できる形で置く。
- workflow、schema policy、検証方針を変えたら AI 向け文書も更新する。
