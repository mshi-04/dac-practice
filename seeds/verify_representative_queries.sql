-- verify_representative_queries.sql
--
-- docs/ecommerce-data-model.md の「Aurora の代表 query」を実データ付きで確認する。
-- 前提: migrations、seeds/ecommerce_local_seed.sql、sql/functions/*.sql を適用済み。
-- checkout と検証用の配送 event はこの transaction の中だけで作り、最後に ROLLBACK する。

\set ON_ERROR_STOP on

BEGIN;

\echo '=== 検証用 checkout を作成 ==='
SELECT txid_current()::TEXT AS verify_suffix \gset

SELECT checkout_place_order(
    (SELECT id FROM customers WHERE email = 'yuki.sato@example.test'),
    'LOCAL-SEED-VERIFY-' || :'verify_suffix',
    'JPY',
    500.00,
    0.00,
    jsonb_build_array(
        jsonb_build_object(
            'product_id', (SELECT id FROM products WHERE sku = 'SEED-NOTEBOOK-A5-001'),
            'quantity', 2,
            'expected_unit_price', 480.00
        )
    ),
    jsonb_build_array(
        jsonb_build_object(
            'address_type', 'shipping',
            'recipient_name', '佐藤 優希',
            'postal_code', '100-0001',
            'region', '東京都',
            'city', '千代田区',
            'address_line1', '千代田 1-1-1',
            'phone_number', '03-1234-5678'
        ),
        jsonb_build_object(
            'address_type', 'billing',
            'recipient_name', '佐藤 優希',
            'postal_code', '100-0001',
            'region', '東京都',
            'city', '千代田区',
            'address_line1', '千代田 1-1-1',
            'phone_number', '03-1234-5678'
        )
    ),
    jsonb_build_object(
        'provider', 'local-seed-pay',
        'provider_payment_id', 'pi_local_seed_' || :'verify_suffix',
        'status', 'authorized',
        'amount', 1460.00,
        'provider_event_id', 'evt_local_seed_' || :'verify_suffix'
    )
) AS order_id \gset

INSERT INTO shipments (order_id, status, carrier, tracking_number, shipped_at)
VALUES (:order_id, 'shipped', 'Local Carrier', 'LOCAL-SEED-TRACK-' || :'verify_suffix', CURRENT_TIMESTAMP)
RETURNING id AS shipment_id \gset

INSERT INTO shipment_events (shipment_id, event_type, location)
VALUES (:shipment_id, 'shipped', 'Tokyo distribution center');

\echo ''
\echo '=== 1. email から顧客を取得 ==='
SELECT id, name, email, status
  FROM customers
 WHERE email = 'yuki.sato@example.test';

\echo ''
\echo '=== 2. 顧客ごとの注文履歴を注文日時の降順で取得 ==='
SELECT order_number, status, total_amount, currency, placed_at
  FROM orders
 WHERE customer_id = (SELECT id FROM customers WHERE email = 'yuki.sato@example.test')
 ORDER BY placed_at DESC;

\echo ''
\echo '=== 3. 注文番号から header、明細、決済、出荷状態を取得 ==='
SELECT o.order_number,
       o.status AS order_status,
       oi.sku,
       oi.product_name,
       oi.quantity,
       oi.unit_price_amount,
       payment.provider,
       payment.status AS payment_status,
       shipment.status AS shipment_status,
       shipment.tracking_number
  FROM orders AS o
  JOIN order_items AS oi ON oi.order_id = o.id
 LEFT JOIN payments AS payment ON payment.order_id = o.id
  LEFT JOIN shipments AS shipment ON shipment.order_id = o.id
 WHERE o.order_number = 'LOCAL-SEED-VERIFY-' || :'verify_suffix'
 ORDER BY oi.id, payment.id, shipment.id;

\echo ''
\echo '=== 4. 販売中の商品をカテゴリ別に取得 ==='
SELECT category.name AS category_name,
       product.sku,
       product.name,
       product.price_amount,
       product.currency,
       inventory.available_quantity - inventory.reserved_quantity AS sellable_quantity
  FROM products AS product
  JOIN product_categories AS category ON category.id = product.category_id
  JOIN inventory_items AS inventory ON inventory.product_id = product.id
 WHERE product.status = 'active'
 ORDER BY category.display_order, category.name, product.name;

\echo ''
\echo '=== 5. 商品の在庫数と引当数を更新 ==='
UPDATE inventory_items AS inventory
   SET reserved_quantity = reserved_quantity + 1,
       updated_at = CURRENT_TIMESTAMP
  FROM products AS product
 WHERE inventory.product_id = product.id
   AND product.sku = 'SEED-COFFEE-BLEND-001'
   AND inventory.available_quantity - inventory.reserved_quantity >= 1
RETURNING product.sku, inventory.available_quantity, inventory.reserved_quantity,
          inventory.available_quantity - inventory.reserved_quantity AS sellable_quantity;

\echo ''
\echo '=== 6. 注文、在庫、決済、配送の event 履歴を時系列で取得 ==='
SELECT event_source, event_type, occurred_at, detail
  FROM (
        SELECT 'order'::TEXT AS event_source,
               event.to_status AS event_type,
               event.occurred_at,
               COALESCE(event.reason, '') AS detail
          FROM order_status_events AS event
         WHERE event.order_id = :order_id
        UNION ALL
        SELECT 'inventory', movement.movement_type, movement.occurred_at,
               product.sku || ': ' || movement.quantity_delta::TEXT
          FROM inventory_movements AS movement
          JOIN products AS product ON product.id = movement.product_id
         WHERE movement.order_id = :order_id
        UNION ALL
        SELECT 'payment', event.event_type, event.occurred_at,
               payment.provider || ': ' || payment.status
          FROM payment_events AS event
          JOIN payments AS payment ON payment.id = event.payment_id
         WHERE payment.order_id = :order_id
        UNION ALL
        SELECT 'shipment', event.event_type, event.occurred_at,
               COALESCE(event.location, '')
          FROM shipment_events AS event
          JOIN shipments AS shipment ON shipment.id = event.shipment_id
         WHERE shipment.order_id = :order_id
       ) AS events
 ORDER BY occurred_at, event_source, event_type;

ROLLBACK;

\echo ''
\echo '検証用の注文・引当・決済・配送 event は ROLLBACK しました。seed data は残ります。'
