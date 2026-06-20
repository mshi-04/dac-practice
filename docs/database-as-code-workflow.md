# Database as Code Workflow

## 基本方針

このプロジェクトでは、Database as Code を次の 4 層に分けて扱う。

1. AWS resource definition: Aurora cluster、DynamoDB table、network、parameter、backup。
2. Relational schema migration: Aurora の table、index、constraint、view、function。
3. NoSQL data model definition: DynamoDB の access pattern、key design、secondary index。
4. Operational policy: encryption、backup、restore、retention、monitoring、cost guardrail。

これらは同じ PR に混ぜすぎない。影響範囲と reviewer の責務が追える単位に分ける。

## Aurora と DynamoDB の責務分離

- Aurora は relational consistency、transaction、SQL query、join、foreign key が必要な
  データに使う想定。
- DynamoDB は key-value / document access、predictable low-latency query、高い
  scale-out が必要なデータに使う想定。
- EC サイトでは、注文確定、在庫引当、決済状態更新の source of truth は Aurora に置き、
  カート、閲覧履歴、lookup cache は DynamoDB の access pattern として別に設計する。
- checkout workflow を変える場合は、Aurora transaction 境界、DynamoDB 同期、失敗時の
  forward fix 方針を同じ PR で review できるようにする。
- どちらに置くか迷う場合は、先に access pattern、整合性要件、transaction 境界、
  query pattern、想定 scale、cost sensitivity を文書化する。

## 変更の流れ

1. 変更目的を書く。
2. 対象 DB を Aurora / DynamoDB / both に分類する。
3. access pattern または relational invariant を明確にする。
4. desired state を code として変更する。
5. migration または resource plan を生成する。
6. generated change を review する。
7. local で可能な検証を実行する。
8. 未検証の範囲を完了報告に残す。

## source of truth

- Aurora schema の source of truth は Atlas migration と schema 定義の組み合わせで扱う。
- DynamoDB の source of truth は table/index 定義と access pattern 文書で扱う。
- AWS resource の source of truth は採用した IaC tool の code と state で扱う。
- AWS console での手動変更は drift として扱い、code に反映するか戻す。

## Atlas Registry 公開

- PR では migration の検証だけを行い、Atlas Registry は更新しない。
- `develop` にマージされ、`migrations/` または `atlas.hcl` が変わったときだけ
  `Publish Atlas Registry` workflow が `dacpractice` を更新する。
- workflow は GitHub Actions Secret の `ATLAS_TOKEN` に保存した Atlas Cloud の Bot token を使う。
  Bot は organization settings で作成し、token は repository や workflow 定義に保存しない。
- 同時実行を直列化し、先に開始した公開処理を途中で取り消さない。
- Registry は migration directory の配布・確認用であり、Aurora への適用は別の
  deployment workflow で明示的に扱う。

## Migration file format

- `migrations/*.sql` と `migrations/atlas.sum` は `.gitattributes` で LF に固定する。
- Atlas の checksum は migration file のバイト列を比較するため、Windows の CRLF 変換を
  許可しない。

## 採用 tool の考え方

- Aurora の SQL schema migration には Atlas を使う。
- Aurora cluster や DynamoDB table など AWS resource には Terraform、AWS CDK、
  CloudFormation のいずれかを後続で選ぶ。
- DynamoDB は SQL migration ではなく、table/index/access pattern の変更として review する。

## 公式 reference

- Aurora best practices: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html
- Aurora blue/green deployment best practices: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments-best-practices.html
- DynamoDB best practices: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html
- DynamoDB data modeling: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/data-modeling.html
- CloudFormation DynamoDB table reference: https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-dynamodb-table.html
