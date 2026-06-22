# sql/ — checkout 処理の実装

`docs/ecommerce-checkout.md` で定義した checkout の transaction 境界を、Aurora
PostgreSQL-compatible（PG16）で動く PL/pgSQL 関数として実装したものです。Aurora を
source of truth とし、checkout を単一トランザクションで直列化します。

`schema.sql` / `migrations/` のテーブル定義は変更しません。ここに置くのは、その上で動く
再利用可能な application レベルの関数とデモ用データです（Atlas の管理対象外）。

## 構成

```text
sql/
├── functions/
│   ├── checkout_place_order.sql      checkout 本体（在庫再確認・引当・注文・決済を 1 関数で）
│   ├── inventory_release_order.sql   注文取消時の在庫戻し（reserved を減らし released に）
│   ├── inventory_consume_order.sql   出荷時の在庫消費（available と reserved を減らし consumed に）
│   └── inventory_adjust.sql          入庫・棚卸・手動調整（stock_in / adjust）
└── examples/
    ├── sample_data.sql               デモ用の顧客・商品・在庫
    └── demo_checkout.sql             成功 → 在庫不足で失敗 → 取消 → 出荷の一連
```

## 関数の概要

| 関数 | 用途 | 戻り値 |
| --- | --- | --- |
| `checkout_place_order(...)` | 販売状態・価格・在庫の再確認、oversell しない在庫引当、注文/明細/住所 snapshot 作成、決済記録 | 作成した `orders.id` |
| `inventory_release_order(order_id, reason)` | 注文取消。引当を解放し注文を `canceled` に | 解放した引当件数 |
| `inventory_consume_order(order_id, reason)` | 出荷。引当を消費し在庫総数を減らす | 消費した引当件数 |
| `inventory_adjust(product_id, delta, type, reason)` | 入庫・棚卸・手動調整 | なし |

### oversell の防止

在庫引当は、`available_quantity - reserved_quantity >= :quantity` を条件にした単一 `UPDATE`
で行います。read と write の間に別の checkout が割り込んでも、行 lock により条件を満たした
1 件だけが更新されます。更新 0 件なら在庫不足として例外を投げ、transaction 全体が rollback
します（`docs/ecommerce-checkout.md` の在庫引当方針）。

### `inventory_movements.quantity_delta` の符号規約

「販売可能数（`available_quantity - reserved_quantity`）への符号付き増減」を表します。

| movement_type | 符号 | 意味 |
| --- | --- | --- |
| `stock_in` | + | 入庫で販売可能数が増える |
| `reserve` | − | checkout 引当で販売可能数が減る |
| `release` | + | 取消で引当が戻る |
| `ship` | − | 出荷で在庫が出ていく |
| `adjust` | ± | 棚卸・手動調整 |

### 決済 authorization の失敗時

`docs/ecommerce-checkout.md` の選択肢のうち「注文作成前に失敗させる」を採用しています。
`payment.status` が `authorized` 以外の場合、`checkout_place_order` は注文を作らず例外で
rollback します。失敗 authorization の監査記録が必要な場合は、この関数の外で `payment_events`
に残してください。

## 動かし方（local validation）

Docker と Atlas が使える環境での手順です。

```powershell
# 1. 空の PostgreSQL 16 を起動し schema を適用する
docker compose up -d db
$env:DATABASE_URL = "postgres://app:app_password@localhost:5432/appdb?search_path=public&sslmode=disable"
atlas migrate apply --env local

# 2. 関数を登録する
$pg = "postgres://app:app_password@localhost:5432/appdb?sslmode=disable"
psql $pg -f sql/functions/checkout_place_order.sql
psql $pg -f sql/functions/inventory_release_order.sql
psql $pg -f sql/functions/inventory_consume_order.sql
psql $pg -f sql/functions/inventory_adjust.sql

# 3. サンプルデータを投入し、デモを実行する
psql $pg -f sql/examples/sample_data.sql
psql $pg -f sql/examples/demo_checkout.sql
```

`psql` を単体で持たない場合は、起動済みコンテナ経由でも実行できます。

```powershell
docker compose cp sql dac-practice-db:/tmp/sql
docker compose exec -T db psql -U app -d appdb -f /tmp/sql/functions/checkout_place_order.sql
# ... 他の関数 / sample_data.sql / demo_checkout.sql も同様
```

`demo_checkout.sql` は次を順に示します。

1. checkout 成功（在庫の `reserved_quantity` が増える）
2. 在庫不足の checkout が例外で rollback し、注文が作られない
3. 注文取消で引当が戻り注文が `canceled` になる
4. 出荷で `available_quantity` と `reserved_quantity` が同量減り、引当が `consumed` 状態になる
