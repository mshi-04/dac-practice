# EC Site Data Model

## 目的

この文書は、EC サイトを想定した RDS PostgreSQL と DynamoDB の責務分離を定義する。

RDS PostgreSQL は注文、商品、在庫、支払いなど relational integrity と transaction が必要な
record を扱う。DynamoDB はカート、閲覧履歴、セッション状態など、key-value access と
低 latency を優先する read/write pattern を扱う。

## RDS PostgreSQL の対象

RDS PostgreSQL schema では、次の aggregate を管理する。

- `customers`: 顧客の基本情報。email は一意にする。
- `customer_addresses`: 顧客の配送先、請求先住所。
- `product_categories`: 商品カテゴリ。親子関係を持てる。
- `products`: 商品 master。SKU、価格、販売状態を持つ。
- `inventory_items`: 商品ごとの販売可能数、引当数、発注目安。
- `orders`: 注文 header。顧客、状態、金額合計、注文日時を持つ。
- `order_addresses`: 注文時点の配送先、請求先住所 snapshot。
- `order_items`: 注文明細。注文時点の商品名、SKU、単価を snapshot として持つ。
- `order_status_events`: 注文状態の遷移履歴。
- `inventory_reservations`: 注文単位の商品在庫引当。
- `inventory_movements`: 在庫増減の監査履歴。
- `payments`: 決済 provider の決済 ID と状態。
- `payment_events`: 決済 provider との event 履歴。
- `shipments`: 出荷状態と追跡番号。
- `shipment_events`: 配送 provider との event 履歴。

注文後に商品名や価格が変わっても注文履歴が変わらないように、`order_items` は
`products` への参照に加えて `sku`、`product_name`、`unit_price_amount` を保持する。
住所も同様に、顧客住所を参照するだけではなく `order_addresses` に注文時点の snapshot を残す。

## PostgreSQL の代表 query

- email から顧客を取得する。
- 顧客ごとの注文履歴を注文日時の降順で取得する。
- 注文番号から注文 header、明細、決済、出荷状態を取得する。
- 販売中の商品をカテゴリ別に取得する。
- 商品の在庫数と引当数を更新する。
- 注文、在庫、決済、配送の event 履歴を時系列で取得する。

## DynamoDB の対象

DynamoDB は relational model をそのまま写さず、次の access pattern を優先して設計する。
Terraform の table 定義は `infra/terraform/dynamodb.tf` に置く。RDS PostgreSQL は注文、在庫、決済の
source of truth を担い、DynamoDB はカート、活動履歴、注文 lookup cache を担う。

### ShoppingCart table

- 目的: 顧客または匿名 session の現在のカートを低 latency で読む。
- Terraform resource: `aws_dynamodb_table.shopping_cart`
- Partition key（physical attribute）: `cart_owner_id` / `S`
- Sort key（physical attribute）: `item_id` / `S`
- 主な access pattern:
  - `cart_owner_id` でカート内 item を一覧する。
  - `cart_owner_id` + `item_id` で数量を更新する。
- TTL: 有効。`expires_at_epoch` を Unix epoch 秒で設定し、一定期間更新のない匿名カートを削除する。
- 整合性: checkout 直前に RDS PostgreSQL の商品価格と在庫を再確認する。checkout 成功後は snapshot の
  `cart_revision` を条件に item を削除し、更新済み item を誤って削除しない。

### CustomerActivity table

- 目的: 閲覧履歴、検索履歴、商品閲覧 event を時系列で保存する。
- Terraform resource: `aws_dynamodb_table.customer_activity`
- Partition key（physical attribute）: `customer_or_session_id` / `S`
- Sort key（physical attribute）: `occurred_at_event_id` / `S`。論理表現の `occurred_at#event_id` を
  Terraform で扱いやすい物理属性名にしたもの。
- 主な access pattern:
  - 顧客または session ごとの直近 activity を取得する。
- TTL: 有効。`expires_at_epoch` を event 発生時刻から 30 日後の Unix epoch 秒で設定する。TTL の
  物理削除を待たず、読み取り時にも期限切れ item を除外する。
- 注意: 分析用途の大規模集計は DynamoDB table scan ではなく、TTL 前の stream/export による
  別保存先を設計する。

### OrderLookup table

- 目的: 外部向け注文番号や問い合わせ token から注文 ID を低 latency で解決する。
- Terraform resource: `aws_dynamodb_table.order_lookup`
- Partition key（physical attribute）: `lookup_key` / `S`
- Sort key: なし。
- 主な access pattern:
  - `ORDER#<order_number>` から RDS PostgreSQL の `orders.id` を取得する。
  - `PAYMENT#<provider>#<provider_payment_id>` から RDS PostgreSQL の `payments.id` を取得する。
- TTL: 有効。`expires_at_epoch` に cache 作成から 30 日後の Unix epoch 秒を設定する。
- 注意: source of truth は RDS PostgreSQL とし、TTL による cache miss と target の不整合時は RDS PostgreSQL から
  再生成する。item 契約と回復手順は
  [EC DynamoDB 整合性回復フロー](ecommerce-consistency-recovery.md) を参照する。

## Review 時の注意

- 注文確定、在庫引当、決済状態更新は PostgreSQL transaction 境界として review する。
- カートと閲覧履歴は DynamoDB の TTL、hot partition、item size を review する。
- DynamoDB item に商品説明や画像など大きな blob を持たせない。
- lookup cache、checkout 後のカート削除、activity の TTL 失効は
  [EC DynamoDB 整合性回復フロー](ecommerce-consistency-recovery.md) に従う。
