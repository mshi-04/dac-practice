# DynamoDB Guidelines

## 目的

DynamoDB は relational schema から始めない。access pattern から table、partition key、
sort key、secondary index を設計する。

## access pattern first

table を作る前に、少なくとも次を書く。

- 誰が読むか
- 何を key に読むか
- 何件返る想定か
- sort が必要か
- 書き込み頻度
- item size
- TTL が必要か
- 強い整合性が必要か

## key design

- partition key は高 cardinality を優先する。
- hot partition を避ける。
- sort key は range query、時系列、階層表現に使う。
- single-table design と multiple-table design は、access pattern と学習目的に応じて選ぶ。
- relational model をそのまま table 分割に写さない。

## secondary index

- GSI は query requirement から追加する。
- GSI は write cost と storage cost を増やす前提で review する。
- LSI は table 作成時の設計判断として扱う。
- index 追加時は backfill と運用影響を確認する。

## operation policy

学習用でも、table 定義では次を意図的に扱う。

- billing mode
- point-in-time recovery
- deletion protection
- server-side encryption
- TTL
- Streams
- resource policy
- tags

## review anti-patterns

- access pattern がないまま table を作る。
- RDB の table をそのまま DynamoDB table に移す。
- low-cardinality key を partition key にする。
- GSI を「あとで検索しそう」という理由だけで追加する。
- large blob を item に直接持たせる。
