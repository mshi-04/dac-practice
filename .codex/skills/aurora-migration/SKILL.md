---
name: aurora-migration
description: Aurora PostgreSQL schema migration with Atlas. Use when changing relational schema (tables, columns, indexes, constraints, views, functions), generating, linting, or testing migrations, or applying schema changes to Aurora.
---

# Aurora Migration

Aurora PostgreSQL の relational schema を Atlas の versioned migration で変更するときに使う。

## 参照

判断基準の詳細は docs を読む（この skill には複製しない）。

- Aurora schema / migration 方針: [aurora-guidelines](../../../docs/aurora-guidelines.md)
- 全体の流れ: [dac-workflow](../../../docs/dac-workflow.md)

## 手順

1. `atlas schema inspect --env local` で現状を把握する。
2. `schema.sql` など schema source を編集する。
3. `atlas schema validate --env local` で構文・整合を確認する。
4. `atlas migrate diff --env local "<動詞_対象>"` で migration を生成する。
5. `atlas migrate lint --env local --latest 1` で破壊的変更・後方互換性を確認する。
6. `atlas migrate test --env local` でテストする（atlas login が要る場合あり）。
7. `atlas migrate apply --env local --dry-run` で preview してから apply する。
8. `atlas migrate status --env local` で状態を確認する。

## 注意

- destructive change（DROP、型変更）と backfill は分割し、安全な順序で段階適用する。
- migration file を手で編集したら `atlas migrate hash --env local` を実行する。
- production 適用は別 workflow。rollback ではなく forward fix を基本にする。
