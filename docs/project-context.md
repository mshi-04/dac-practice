# プロジェクトコンテキスト

## 目的

DacPractice は Database as Code を管理するリポジトリです。

このプロジェクトは、database 変更を review・検証・運用できる状態で Git に残すことを優先します。
練習用の domain は EC サイトを想定します。

- AWS database resource を code として表現する。
- RDS PostgreSQL の relational schema change を migration として review する。
- DynamoDB の table design を access pattern から設計する。
- schema、migration、capacity、backup、security policy を Git 上で履歴管理する。
- local 検証、CI、cloud 適用、rollback/forward fix の境界を明確にする。

## 現在の技術スタック

- Relational database: Amazon Amazon RDS for PostgreSQL 16
- Key-value / document database: Amazon DynamoDB
- Relational schema migration: Atlas
- AWS resource definition: Terraform
- Local validation target: Docker Compose などの local database を必要に応じて使う
- Repository hosting: GitHub

## リポジトリ構成

- `docs/`: AI と開発者向けの詳細な判断基準。
- `migrations/`: RDS PostgreSQL 向けの versioned migration。
- `schema.sql`: RDS PostgreSQL の relational schema 定義。後続で配置を見直してよい。
- `atlas.hcl`: Atlas の local environment と migration 設定。
- `infra/`: Terraform による AWS resource 定義。
- `docker-compose.yml`: local 検証環境。AWS 実リソースの代替ではない。
- `AGENTS.md`: Codex 向けの repo 全体に効く薄い永続指示。
- `CLAUDE.md`: Claude Code 向けの永続指示。`AGENTS.md` と同内容で skill のパスだけが異なる。
- `.agents/skills/`: 作業領域ごとに分けた Codex 用 skill（`rds-migration`、`dynamodb-modeling`、
  `aws-resource`、`change-review`）。
- `.codex/skills/`: Atlas の Codex 用 skill。
- `.claude/skills/`: Claude Code 用 skill。`.agents/skills/` と `.codex/skills/atlas/` に対応する。

## ブランチ運用

- `main`: 安定版の default branch。
- `develop`: 統合 branch。
- feature 作業は `develop` から切る。
- branch 名は `feature/<topic>` を使う。

## 設計方針

- RDS PostgreSQL と DynamoDB は同じ「Database」でも設計原則が異なるため、同じ schema
  guideline に混ぜない。
- RDS PostgreSQL は PostgreSQL-compatible を前提に relational integrity、transaction、SQL migration を扱う。
- DynamoDB は access pattern、partition key、sort key、secondary index、capacity を
  明示的に設計する。
- EC サイトの注文、商品、在庫、決済は RDS PostgreSQL を source of truth とし、カート、閲覧履歴、
  lookup cache は DynamoDB の access pattern として分けて review する。
- destructive change、data loss、capacity/cost、backup/restore、security は
  影響範囲を明示して review する。
- seed data、sample data、fixture は schema や AWS resource 定義と混ぜない。
