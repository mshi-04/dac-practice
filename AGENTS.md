# AGENTS.md

## プロジェクト

このリポジトリは、AWS の RDS PostgreSQL と DynamoDB を対象に、Database as Code の
設計・検証・運用方針を管理するプロジェクトです。

変更前に必要な範囲で以下を読むこと。

- [docs/rds-postgres-guidelines.md](docs/rds-postgres-guidelines.md)
- [docs/aws-resource-guidelines.md](docs/aws-resource-guidelines.md)
- [docs/change-review-guidelines.md](docs/change-review-guidelines.md)
- [docs/dac-workflow.md](docs/dac-workflow.md)
- [docs/dynamodb-guidelines.md](docs/dynamodb-guidelines.md)
- [docs/ecommerce-checkout.md](docs/ecommerce-checkout.md)
- [docs/ecommerce-data-model.md](docs/ecommerce-data-model.md)
- [docs/project-context.md](docs/project-context.md)

## skill

作業領域ごとに skill を分けている。正本は `.agents/skills/` とする。Codex は正本を直接参照し、
Claude Code 用の `.claude/skills/` は同期生成する。手順は [docs/claude-code.md](docs/claude-code.md) を参照する。

- [atlas](.codex/skills/atlas/SKILL.md): Atlas 公式文書として取り込んだ schema / migration 操作用 skill（この skill のみ `.codex/` から直接参照）。

- [rds-migration](.agents/skills/rds-migration/SKILL.md): RDS PostgreSQL schema を Atlas で migration。
- [aws-resource](.agents/skills/aws-resource/SKILL.md): AWS resource を Terraform で定義（`infra/`）。
- [change-review](.agents/skills/change-review/SKILL.md): Database as Code 変更の review。
- [dynamodb-modeling](.agents/skills/dynamodb-modeling/SKILL.md): DynamoDB の access pattern と key design。

## 作業ルール

- `AGENTS.md` と各 skill は薄く保ち、詳細な判断基準は `docs/` に置く。
- 作業は次の共通手順で進める。
  1. `git status -sb` で branch と作業ツリーを確認する。
  2. 変更対象を RDS PostgreSQL / DynamoDB / Terraform resource / docs に分類し、対応する skill と docs を読む。
  3. 作業を行う。
- workflow、schema policy、検証方針を変えたら docs と skill を更新する。
