# プロジェクトコンテキスト

## 目的

DacPractice は Database as Code を管理するリポジトリです。

このプロジェクトは、database 変更を review・検証・運用できる状態で Git に残すことを優先します。
練習用の domain は EC サイトを想定します。

- AWS database resource を code として表現する。
- Aurora の relational schema change を migration として review する。
- DynamoDB の table design を access pattern から設計する。
- schema、migration、capacity、backup、security policy を Git 上で履歴管理する。
- local 検証、CI、cloud 適用、rollback/forward fix の境界を明確にする。

## 現在の技術スタック

- Relational database: Amazon Aurora PostgreSQL-compatible Edition
- Key-value / document database: Amazon DynamoDB
- Relational schema migration: Atlas
- AWS resource definition: Terraform、AWS CDK、CloudFormation のいずれかを後続で選定する
- Local validation target: Docker Compose などの local database を必要に応じて使う
- Repository hosting: GitHub

## リポジトリ構成

- `docs/`: AI と開発者向けの詳細な判断基準。
- `migrations/`: Aurora 向けの versioned migration。
- `schema.sql`: Aurora PostgreSQL-compatible の relational schema 定義。後続で配置を見直してよい。
- `atlas.hcl`: Atlas の local environment と migration 設定。
- `docker-compose.yml`: local 検証環境。AWS 実リソースの代替ではない。
- `AGENTS.md`: repo 全体に効く薄い永続指示。
- `.agents/skills/dac-practice/SKILL.md`: DacPractice 作業用 skill。

## ブランチ運用

- `main`: 安定版の default branch。
- `develop`: 統合 branch。
- feature 作業は `develop` から切る。
- branch 名は `feature/<topic>` を使う。

## 設計方針

- Aurora と DynamoDB は同じ「Database」でも設計原則が異なるため、同じ schema
  guideline に混ぜない。
- Aurora は PostgreSQL-compatible を前提に relational integrity、transaction、SQL migration を扱う。
- DynamoDB は access pattern、partition key、sort key、secondary index、capacity を
  明示的に設計する。
- EC サイトの注文、商品、在庫、決済は Aurora を source of truth とし、カート、閲覧履歴、
  lookup cache は DynamoDB の access pattern として分けて review する。
- destructive change、data loss、capacity/cost、backup/restore、security は
  影響範囲を明示して review する。
- seed data、sample data、fixture は schema や AWS resource 定義と混ぜない。
