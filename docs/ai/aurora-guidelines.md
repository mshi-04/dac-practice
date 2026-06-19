# Aurora Guidelines

## 目的

Aurora は relational database として扱う。Database as Code では、AWS resource 定義と
SQL schema migration を分けて review できる状態を目指す。

## engine 選定

Aurora には MySQL-compatible と PostgreSQL-compatible がある。engine を決めるまでは、
engine 固有の SQL、型、extension、migration assumption を固定しない。

engine を決める PR では、少なくとも次を文書化する。

- 採用 engine
- 採用理由
- local 検証方法
- migration tool
- production 相当で気にする制約

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
- long-running DDL と lock の影響を確認する。

## AWS resource

Aurora cluster 定義では、学習用でも次を意図的に扱う。

- subnet / security group
- encryption
- backup retention
- deletion protection
- parameter group
- monitoring / logging
- secret management

## blue/green と schema change

Aurora の blue/green deployment を使う想定では、schema change が replication に与える
影響を確認する。特に table rename や column rename は慎重に扱う。
