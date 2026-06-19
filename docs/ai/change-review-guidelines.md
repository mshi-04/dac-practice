# Change Review Guidelines

## 目的

Database as Code の変更は、application code の変更と同じように review 可能であるべきです。
この文書は、Aurora、DynamoDB、AWS resource 定義、migration の変更を見る観点をまとめます。

## review の基本観点

- 変更対象が Aurora か DynamoDB か、または AWS resource 定義かが明確か。
- desired state と実際に適用される変更の差分が review できるか。
- data loss、lock、長時間実行、既存 data との不整合が起きないか。
- capacity、cost、backup、restore、encryption、network exposure への影響が分かるか。
- local 検証で何を実行し、何が未検証かが分かるか。
- docs/ai の方針と実際の変更がずれていないか。

## Aurora migration の確認観点

- `DROP TABLE`、`DROP COLUMN`、型変更など destructive な操作が含まれていないか。
- `NOT NULL` 追加時に既存 data を考慮しているか。
- unique constraint 追加時に重複 data を考慮しているか。
- foreign key 追加時に orphan record を考慮しているか。
- index 追加が query pattern と対応しているか。
- generated SQL が意図しない rename を drop/add として扱っていないか。
- long-running DDL、lock、replication、blue/green deployment への影響を確認したか。

## DynamoDB 変更の確認観点

- access pattern が文書化されているか。
- partition key が hot partition を生みにくいか。
- sort key が query と lifecycle に合っているか。
- GSI/LSI の追加が write cost、storage cost、backfill に与える影響を見ているか。
- TTL、Streams、PITR、backup、encryption、resource policy の有無が意図と合うか。
- table replacement や index recreation が必要になる変更ではないか。

## AWS resource 定義の確認観点

- state 管理、環境分離、命名規則、tagging が一貫しているか。
- secret を code に含めていないか。
- IAM permission が最小権限になっているか。
- production 相当の削除保護、backup、snapshot、retention を意図的に扱っているか。

## 完了条件

変更完了時は、少なくとも次を確認する。

```powershell
git status -sb
git diff --check
```

Aurora migration や local database practice を変更した場合は、使える環境に応じて次も確認する。

```powershell
atlas migrate validate --env local
docker compose up -d db
atlas migrate apply --env local
```

AWS resource 定義を追加した場合は、採用した IaC tool の validate/plan/synth を実行する。
例:

```powershell
terraform fmt -check
terraform validate
terraform plan
```

使えない command がある場合は、完了報告に理由を明記する。
