# 0001. Aurora PostgreSQL-compatible を採用する

## Status

Accepted

## Context

DacPractice は Aurora の relational schema change を migration として review する
学習リポジトリです。

Aurora には MySQL-compatible と PostgreSQL-compatible があるため、engine を決めるまでは
engine 固有の SQL、型、local 検証方法、migration 前提を固定できません。

既存の local practice scaffolding は次の前提に寄っています。

- `schema.sql` は PostgreSQL の `BIGINT GENERATED ALWAYS AS IDENTITY` と
  `TIMESTAMPTZ` を使っている。
- `atlas.hcl` は PostgreSQL URL と `docker://postgres/16/dev` を使っている。
- `docker-compose.yml` は PostgreSQL 16 container を local target としている。

## Decision

このリポジトリでは Aurora の学習対象を
Amazon Aurora PostgreSQL-compatible Edition として扱います。

Relational schema migration には Atlas を使います。local practice target は
PostgreSQL 16 container とし、AWS 上の Aurora cluster resource 定義とは分けて扱います。

## Rationale

- 既存の SQL と local tooling が PostgreSQL 前提で揃っている。
- Atlas の local diff / validate / apply workflow を小さく試しやすい。
- Aurora resource 定義を追加する前に、schema migration の review 単位を確立できる。

## Local validation

Atlas と Docker が使える環境では、Aurora schema practice の変更ごとに次を確認します。

```powershell
docker compose up -d db
atlas migrate validate --env local
atlas migrate apply --env local
```

Atlas で migration を生成した場合は、migration SQL と checksum の両方を review 対象にします。

## Production considerations

この決定は local migration practice の前提を決めるものです。production 相当の Aurora cluster
resource 定義はまだ選定していません。

後続で AWS resource definition を追加する PR では、少なくとも次を別途 review します。

- engine family と version
- cluster / instance topology
- subnet group と security group
- encryption と secret management
- backup retention と deletion protection
- log export、monitoring、parameter group

## Consequences

- Aurora schema の SQL は PostgreSQL-compatible を前提に書ける。
- MySQL-compatible 固有の SQL や migration assumption はこの repo では扱わない。
- DynamoDB の table/access pattern 設計は、この決定とは独立して扱う。
