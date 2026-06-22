-- demo_checkout.sql
--
-- checkout / 在庫戻し / 在庫消費の一連を 1 スクリプトで実演する。
-- 前提: schema 適用済み DB に sql/functions/*.sql と sql/examples/sample_data.sql を投入済み。
-- 実行例: psql "$DATABASE_URL" -f sql/examples/demo_checkout.sql

\set ON_ERROR_STOP on

\echo '=== 0. 在庫の初期状態 ==='
SELECT p.sku, i.available_quantity, i.reserved_quantity,
       i.available_quantity - i.reserved_quantity AS sellable
  FROM inventory_items i JOIN products p ON p.id = i.product_id
 WHERE p.sku LIKE 'DEMO-%'
 ORDER BY p.sku;

\echo ''
\echo '=== 1. checkout 成功（SKU-001 x2, SKU-002 x1）==='
SELECT checkout_place_order(
    (SELECT id FROM customers WHERE email = 'demo.buyer@example.com'),
    'DEMO-0001',
    'JPY',
    500.00,   -- shipping
    0.00,     -- tax
    jsonb_build_array(
        jsonb_build_object('product_id', (SELECT id FROM products WHERE sku = 'DEMO-SKU-001'),
                           'quantity', 2, 'expected_unit_price', 1980.00),
        jsonb_build_object('product_id', (SELECT id FROM products WHERE sku = 'DEMO-SKU-002'),
                           'quantity', 1, 'expected_unit_price', 990.00)
    ),
    jsonb_build_array(
        jsonb_build_object('address_type','shipping','recipient_name','Demo Buyer',
                           'postal_code','100-0001','region','Tokyo','city','Chiyoda',
                           'address_line1','1-1-1'),
        jsonb_build_object('address_type','billing','recipient_name','Demo Buyer',
                           'postal_code','100-0001','region','Tokyo','city','Chiyoda',
                           'address_line1','1-1-1')
    ),
    jsonb_build_object('provider','demo-pay','provider_payment_id','pi_demo_0001',
                       'status','authorized','amount',5450.00,
                       'provider_event_id','evt_demo_0001')
) AS created_order_id;

\echo '--- 注文・引当・決済の結果 ---'
SELECT order_number, status, subtotal_amount, shipping_fee_amount, total_amount
  FROM orders WHERE order_number = 'DEMO-0001';
SELECT p.sku, r.quantity, r.status
  FROM inventory_reservations r JOIN products p ON p.id = r.product_id
 WHERE r.order_id = (SELECT id FROM orders WHERE order_number = 'DEMO-0001')
 ORDER BY p.sku;
SELECT pr.provider, pr.status, pr.amount FROM payments pr
 WHERE pr.order_id = (SELECT id FROM orders WHERE order_number = 'DEMO-0001');

\echo '--- 在庫（reserved が増えている）---'
SELECT p.sku, i.available_quantity, i.reserved_quantity,
       i.available_quantity - i.reserved_quantity AS sellable
  FROM inventory_items i JOIN products p ON p.id = i.product_id
 WHERE p.sku LIKE 'DEMO-%' ORDER BY p.sku;

\echo ''
\echo '=== 2. checkout 失敗：在庫不足（SKU-002 を残数以上に要求）==='
\echo '    DO ブロックで例外を捕捉し、注文が作成されない（rollback される）ことを示す。'
DO $$
BEGIN
    PERFORM checkout_place_order(
        (SELECT id FROM customers WHERE email = 'demo.buyer@example.com'),
        'DEMO-0002',
        'JPY', 0.00, 0.00,
        jsonb_build_array(
            jsonb_build_object('product_id', (SELECT id FROM products WHERE sku = 'DEMO-SKU-002'),
                               'quantity', 99)
        ),
        '[]'::jsonb,
        jsonb_build_object('provider','demo-pay','provider_payment_id','pi_demo_0002',
                           'status','authorized')
    );
    RAISE NOTICE 'UNEXPECTED: checkout succeeded despite insufficient stock';
EXCEPTION
    -- 想定する在庫不足（check_violation かつ insufficient stock）だけを成功扱いにし、
    -- 関数未登録・型不整合などの想定外エラーは再送出して握り潰さない。
    WHEN SQLSTATE '23514' THEN
        IF POSITION('insufficient stock' IN SQLERRM) = 0 THEN
            RAISE;
        END IF;
        RAISE NOTICE 'EXPECTED failure (rolled back): %', SQLERRM;
END;
$$;

\echo '--- 失敗注文は存在しない ---'
SELECT count(*) AS demo_0002_orders FROM orders WHERE order_number = 'DEMO-0002';

\echo ''
\echo '=== 3. 注文取消（在庫戻し）：DEMO-0001 を release ==='
SELECT inventory_release_order(
    (SELECT id FROM orders WHERE order_number = 'DEMO-0001'),
    'demo: customer canceled'
) AS released_reservations;

SELECT order_number, status FROM orders WHERE order_number = 'DEMO-0001';
\echo '--- 在庫（reserved が戻る）---'
SELECT p.sku, i.available_quantity, i.reserved_quantity
  FROM inventory_items i JOIN products p ON p.id = i.product_id
 WHERE p.sku LIKE 'DEMO-%' ORDER BY p.sku;

\echo ''
\echo '=== 4. 出荷（在庫消費）：新規注文 DEMO-0003 を checkout して consume ==='
SELECT checkout_place_order(
    (SELECT id FROM customers WHERE email = 'demo.buyer@example.com'),
    'DEMO-0003', 'JPY', 0.00, 0.00,
    jsonb_build_array(
        jsonb_build_object('product_id', (SELECT id FROM products WHERE sku = 'DEMO-SKU-001'),
                           'quantity', 1)
    ),
    jsonb_build_array(
        jsonb_build_object('address_type','shipping','recipient_name','Demo Buyer',
                           'postal_code','100-0001','region','Tokyo','city','Chiyoda',
                           'address_line1','1-1-1')
    ),
    jsonb_build_object('provider','demo-pay','provider_payment_id','pi_demo_0003',
                       'status','authorized')
) AS created_order_id;

SELECT inventory_consume_order(
    (SELECT id FROM orders WHERE order_number = 'DEMO-0003'),
    'demo: shipped'
) AS consumed_reservations;

\echo '--- 在庫（SKU-001 の available と reserved が同量減る）---'
SELECT p.sku, i.available_quantity, i.reserved_quantity
  FROM inventory_items i JOIN products p ON p.id = i.product_id
 WHERE p.sku LIKE 'DEMO-%' ORDER BY p.sku;

\echo '--- 在庫監査ログ（DEMO 範囲）---'
SELECT p.sku, m.movement_type, m.quantity_delta, m.reason
  FROM inventory_movements m JOIN products p ON p.id = m.product_id
 WHERE p.sku LIKE 'DEMO-%'
 ORDER BY m.occurred_at, m.id;
