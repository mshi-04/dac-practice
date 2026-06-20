# AGENTS.md

## プロジェクト

このリポジトリは、AWS の Aurora と DynamoDB を対象に、Database as Code の
設計・検証・運用方針を管理するプロジェクトです。

変更前に必要な範囲で以下を読むこと。

- [docs/project-context.md](docs/project-context.md)
- [docs/dac-workflow.md](docs/dac-workflow.md)
- [docs/aws-resource-guidelines.md](docs/aws-resource-guidelines.md)
- [docs/aurora-guidelines.md](docs/aurora-guidelines.md)
- [docs/dynamodb-guidelines.md](docs/dynamodb-guidelines.md)
- [docs/change-review-guidelines.md](docs/change-review-guidelines.md)

## skill

作業領域ごとに skill を分けている。正本は `.agents/skills/` とする。Codex 用の
`.codex/skills/` と Claude Code 用の `.claude/skills/` は同期生成する。手順は
[docs/claude-code.md](docs/claude-code.md) を参照する。

- [aurora-migration](.codex/skills/aurora-migration/SKILL.md): Aurora schema を Atlas で migration。
- [dynamodb-modeling](.codex/skills/dynamodb-modeling/SKILL.md): DynamoDB の access pattern と key design。
- [aws-resource](.codex/skills/aws-resource/SKILL.md): AWS resource を Terraform で定義（`infra/`）。
- [change-review](.codex/skills/change-review/SKILL.md): Database as Code 変更の review。

## 作業ルール

- `AGENTS.md` と各 skill は薄く保ち、詳細な判断基準は `docs/` に置く。
- 作業は次の共通手順で進める。
  1. `git status -sb` で branch と作業ツリーを確認する。
  2. 変更対象を Aurora / DynamoDB / Terraform resource / docs に分類し、対応する skill と docs を読む。
  3. 変更後に `git diff --check` を実行する。
  4. 実行できなかった検証は理由を完了報告に残す。
- review・検証・運用しやすい Database as Code の形を優先する。
- Aurora の schema migration と DynamoDB の table/access pattern 設計を分けて扱う。
- AWS resource 定義、schema 定義、migration、運用 policy を code review できる形で置く。
- workflow、schema policy、検証方針を変えたら docs と skill を更新する。
