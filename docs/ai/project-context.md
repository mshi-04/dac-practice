# プロジェクトコンテキスト

## 目的

DacPractice は Database as Code を学ぶためのリポジトリです。

このプロジェクトは小さく明示的に保ち、学習者が次の流れを追える状態を優先します。

- AWS database resource を code として表現する
- Aurora の relational schema change を migration として review する
- DynamoDB の table design を access pattern から設計する
- schema、migration、capacity、backup、security policy を Git 上で履歴管理する
- local 検証と cloud 適用の境界を明確にする

## 現在の技術スタック

- Relational database: Amazon Aurora
- Key-value / document database: Amazon DynamoDB
- Relational schema migration: Atlas を候補として扱う
- AWS resource definition: Terraform、AWS CDK、CloudFormation のいずれかを後続で選定する
- Local practice target: Docker Compose などの local database を必要に応じて使う
- Repository hosting: GitHub

## リポジトリ構成

- `docs/ai/`: AI 向けの詳細な判断基準。
- `migrations/`: Aurora 向けの versioned migration。
- `schema.sql`: Aurora 学習用の relational schema 定義。後続で配置を見直してよい。
- `atlas.hcl`: Atlas を使う場合の environment と migration 設定。後続で Aurora 前提に見直す。
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
- Aurora は relational integrity、transaction、SQL migration を学ぶ対象にする。
- DynamoDB は access pattern、partition key、sort key、secondary index、capacity を
  学ぶ対象にする。
- destructive change、data loss、capacity/cost、backup/restore、security は学習用でも
  明示的に review する。
- seed data、sample data、fixture は schema や AWS resource 定義と混ぜない。
