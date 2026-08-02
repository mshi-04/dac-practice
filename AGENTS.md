# AGENTS.md

## プロジェクト

このリポジトリは、AWS の RDS PostgreSQL と DynamoDB を対象に、Database as Code の
設計・検証・運用方針を管理するプロジェクトです。

変更前に必要な範囲で以下を読むこと。

- [docs/rds-postgres-guidelines.md](docs/rds-postgres-guidelines.md): RDS PostgreSQL の engine、schema design、migration、deployment の方針。
- [docs/aws-resource-guidelines.md](docs/aws-resource-guidelines.md): Terraform で扱う AWS resource（instance、network、backup、drift）の方針。
- [docs/change-review-guidelines.md](docs/change-review-guidelines.md): Database as Code 変更を review するときの観点。
- [docs/dac-workflow.md](docs/dac-workflow.md): DaC の 4 層分割、Atlas による migration lifecycle、検証環境と production CD。
- [docs/dynamodb-guidelines.md](docs/dynamodb-guidelines.md): access pattern を起点にした table、key、secondary index の設計方針。
- [docs/ecommerce-checkout.md](docs/ecommerce-checkout.md): checkout の transaction 境界と、RDS PostgreSQL と DynamoDB の同期方針。
- [docs/ecommerce-data-model.md](docs/ecommerce-data-model.md): 題材の EC サイトにおける RDS PostgreSQL と DynamoDB の責務分離。
- [docs/project-context.md](docs/project-context.md): リポジトリの目的、構成、branch 運用、設計方針。

## skill

作業領域ごとに分けたプロジェクト固有の skill。`.agents/skills/` に置く。

- [rds-migration](.agents/skills/rds-migration/SKILL.md): RDS PostgreSQL schema を Atlas で migration。
- [aws-resource](.agents/skills/aws-resource/SKILL.md): AWS resource を Terraform で定義（`infra/`）。
- [change-review](.agents/skills/change-review/SKILL.md): Database as Code 変更の review。
- [dynamodb-modeling](.agents/skills/dynamodb-modeling/SKILL.md): DynamoDB の access pattern と key design。

上記 4 つ以外の skill は Atlas（atlasgo）公式文書として取り込んだもので、`.codex/skills/` に置く。

- [atlas](.codex/skills/atlas/SKILL.md): Atlas CLI による schema / migration 操作。
  同じ directory の [AGENTS.md](.codex/skills/atlas/AGENTS.md) は、Atlas 作業時に読み込む
  configuration、workflow、lint の詳細。

## 作業ルール

- `AGENTS.md` と各 skill は薄く保ち、詳細な判断基準は `docs/` に置く。
- 作業は次の共通手順で進める。
  1. `git status -sb` で branch と作業ツリーを確認する。
  2. 変更対象を RDS PostgreSQL / DynamoDB / Terraform resource / docs に分類し、対応する skill と docs を読む。
  3. 作業を行う。
- workflow、schema policy、検証方針を変えたら docs と skill を更新する。
