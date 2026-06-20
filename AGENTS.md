# AGENTS.md

## プロジェクト

このリポジトリは、AWS の Aurora と DynamoDB を対象に、Database as Code の
設計・検証・運用方針を管理するプロジェクトです。

変更前に必要な範囲で以下を読むこと。

- [docs/project-context.md](docs/project-context.md)
- [docs/database-as-code-workflow.md](docs/database-as-code-workflow.md)
- [docs/aws-resource-guidelines.md](docs/aws-resource-guidelines.md)
- [docs/aurora-guidelines.md](docs/aurora-guidelines.md)
- [docs/dynamodb-guidelines.md](docs/dynamodb-guidelines.md)
- [docs/change-review-guidelines.md](docs/change-review-guidelines.md)

## 作業ルール

- `AGENTS.md` は薄く保ち、詳細な判断基準は `docs/` に置く。
- review・検証・運用しやすい Database as Code の形を優先する。
- Aurora の schema migration と DynamoDB の table/access pattern 設計を分けて扱う。
- AWS resource 定義、schema 定義、migration、運用 policy を code review できる形で置く。
- workflow、schema policy、検証方針を変えたら AI 向け文書も更新する。
