# RDS PostgreSQL Guidelines

## 目的

Amazon RDS for PostgreSQL は relational database として扱う。Database as Code では、AWS resource 定義と
SQL schema migration を分けて review できる状態を目指す。

## engine

DacPractice では Amazon RDS for PostgreSQL 16 を対象にする。

## schema design

- table、column、index、constraint は snake_case を使う。
- business invariant は database constraint として表現できるか検討する。
- foreign key は relational integrity が必要な関係に使う。
- index は query pattern と対応付けて追加する。
- destructive change は data loss と rollback/forward fix 方針を明記する。

## migration

- migration は review 可能な SQL として残す。
- 既に共有環境へ適用した migration は原則として書き換えない。
- rename は drop/add として扱われていないか確認する。
- `NOT NULL`、unique constraint、foreign key の追加は既存 data を考慮する。
- 新規 table の invariant は `CREATE TABLE` に constraint として含める。既存 table への constraint 追加は、必要に応じて `NOT VALID`、backfill、`VALIDATE CONSTRAINT` を段階的に行う。
- 既存 table に volatile な default を持つ column を追加するときは、nullable column の追加、batch backfill、default の設定、`NOT NULL` の順に分け、長時間 lock と table rewrite を避ける。
- long-running DDL と lock の影響を確認する。
- `schema.sql` の変更から `atlas migrate diff` で migration を生成し、生成 SQL を review する。
- PR では Atlas lint と migration test を通し、`develop` で公開された Registry SHA tag だけを適用する。
- shared environment の migration failure は rollback の自動実行ではなく forward fix で解消する。

## AWS resource

RDS instance 定義では、運用に必要な次の項目を明示的に扱う。

- subnet / security group
- encryption
- backup retention
- deletion protection
- parameter group
- monitoring / logging
- secret management

## verification deployment

- verification RDS PostgreSQL は private subnet に置き、public endpoint を作らない。
- GitHub Actions から起動する VPC 内 CodeBuild が Atlas Registry から immutable SHA tag を取得して apply する。
- apply 前に dry-run、apply 後に migration status を実行する。
- Registry read token と RDS PostgreSQL credential は Secrets Manager から取得し、build log に出力しない。

## blue/green deployment と schema change

RDS PostgreSQL の blue/green deployment を使う想定では、schema change が replication に与える
影響を確認する。特に table rename や column rename は慎重に扱う。
