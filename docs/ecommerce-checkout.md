# EC Checkout

## 目的

EC サイトの checkout は、カート、注文、在庫、決済、配送の境界がまたがる。
この文書では Aurora を source of truth とする transaction 境界と、DynamoDB との同期方針を定義する。

## Source of truth

- カートの編集中状態は DynamoDB の `ShoppingCart` table に置く。
- 注文確定後の注文、金額、住所 snapshot、在庫引当、決済、配送は Aurora を source of truth にする。
- DynamoDB の lookup cache や activity record は再生成可能な副次データとして扱う。

## Checkout の流れ

1. DynamoDB から `cart_owner_id` のカート item を取得する。
2. Aurora transaction を開始する。
3. `products` と `inventory_items` を読み、販売状態、価格、在庫を再確認する。
4. `orders`、`order_items`、`order_addresses` を作成する。
5. `inventory_items.reserved_quantity` を増やし、`inventory_reservations` と `inventory_movements` を作成する。
6. 決済 provider の authorization 結果を `payments` と `payment_events` に記録する。
7. 成功時は transaction を commit し、DynamoDB のカートを削除または checkout 済みに更新する。

在庫確認と引当は同じ Aurora transaction 内で直列化する。`inventory_items` を
`SELECT ... FOR UPDATE` で lock するか、`available_quantity - reserved_quantity >= :quantity` を
条件にした単一の `UPDATE` を使う。更新件数が 0 件なら在庫不足として transaction を rollback
し、read と write の間に別 checkout が割り込んでも oversell しない。

## 失敗時の扱い

- 商品価格や販売状態が変わっていた場合は、注文を作らず checkout を失敗させる。
- 在庫不足の場合は、注文を作らず checkout を失敗させる。
- 決済 authorization が失敗した場合は、注文を `canceled` にするか、注文作成前に失敗させる。
  どちらを採用したかは application 側の仕様で明示する。
- authorization 後に Aurora commit が失敗した場合は、決済 provider 側で void し、`payment_events` に残す。

## 在庫引当

`inventory_items.available_quantity` は販売可能な総数、`reserved_quantity` は checkout 中または
未出荷の引当数を表す。

- 注文確定時: `reserved_quantity` を増やす。
- 注文取消時: `reserved_quantity` を減らし、`inventory_reservations.status` を `released` にする。
- 出荷時: `available_quantity` と `reserved_quantity` を減らし、`inventory_reservations.status` を `consumed` にする。
- 棚卸や手動調整: `inventory_movements.movement_type = 'adjust'` で理由を残す。

## 住所 snapshot

注文の配送先と請求先は `customer_addresses` を参照するだけではなく、`order_addresses` に
注文時点の住所 snapshot として保存する。顧客が後で住所を変更しても、過去注文の配送記録を変えない。

## Event tables

- `order_status_events`: 注文状態の遷移履歴。
- `inventory_movements`: 在庫増減の監査履歴。
- `payment_events`: 決済 provider との event 履歴。
- `shipment_events`: 配送 provider との event 履歴。

これらは現在状態の source of truth ではなく、監査、障害調査、再送処理の判断材料として扱う。

## DynamoDB 同期

- checkout 成功後、DynamoDB のカート item は削除するか `checked_out` 状態にする。
- `OrderLookup` は Aurora commit 後に非同期で作成してよい。
- lookup cache の作成に失敗しても、Aurora の注文を rollback しない。
- lookup cache は Aurora から再生成できるようにする。
