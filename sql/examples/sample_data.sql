-- sample_data.sql
--
-- checkout 関数のデモ用サンプルデータ。schema は変更しない。
-- 既存 schema（schema.sql / migrations）が適用済みの空 DB に投入する想定。
-- 再実行できるよう、デモ範囲のデータを先に削除してから投入する。

BEGIN;

-- デモ範囲のクリーンアップ。RESTRICT 参照（payments→orders、
-- inventory_reservations/inventory_movements→products）を踏まないよう、子から順に削除する。
--   1. payments（payment_events は CASCADE）を先に消す。
--   2. orders を消す（inventory_reservations / order_items / order_addresses /
--      order_status_events は CASCADE で消える）。
--   3. inventory_movements（products を RESTRICT 参照）を消す。
--   4. inventory_items → products → category → customer。
DELETE FROM payments            WHERE order_id IN (SELECT id FROM orders WHERE order_number LIKE 'DEMO-%');
DELETE FROM orders              WHERE order_number LIKE 'DEMO-%';
DELETE FROM inventory_movements WHERE product_id IN (SELECT id FROM products WHERE sku LIKE 'DEMO-%');
DELETE FROM inventory_items     WHERE product_id IN (SELECT id FROM products WHERE sku LIKE 'DEMO-%');
DELETE FROM products            WHERE sku LIKE 'DEMO-%';
DELETE FROM product_categories  WHERE slug = 'demo-books';
DELETE FROM customers           WHERE email = 'demo.buyer@example.com';

-- 顧客。
INSERT INTO customers (name, email, status)
VALUES ('Demo Buyer', 'demo.buyer@example.com', 'active');

-- カテゴリ。
INSERT INTO product_categories (name, slug, display_order)
VALUES ('Demo Books', 'demo-books', 1);

-- 商品（active と draft を 1 つずつ。draft は販売状態の再確認デモに使う）。
INSERT INTO products (category_id, sku, name, description, status, price_amount, currency)
VALUES
    ((SELECT id FROM product_categories WHERE slug = 'demo-books'),
     'DEMO-SKU-001', 'Demo PostgreSQL Book', 'sample', 'active', 1980.00, 'JPY'),
    ((SELECT id FROM product_categories WHERE slug = 'demo-books'),
     'DEMO-SKU-002', 'Demo Aurora Mug',      'sample', 'active',  990.00, 'JPY'),
    ((SELECT id FROM product_categories WHERE slug = 'demo-books'),
     'DEMO-SKU-003', 'Demo Draft Item',      'sample', 'draft',  500.00, 'JPY');

-- 在庫。available_quantity を販売可能総数、reserved_quantity を引当数とする。
INSERT INTO inventory_items (product_id, available_quantity, reserved_quantity, reorder_threshold)
VALUES
    ((SELECT id FROM products WHERE sku = 'DEMO-SKU-001'), 5, 0, 2),
    ((SELECT id FROM products WHERE sku = 'DEMO-SKU-002'), 3, 0, 1),
    ((SELECT id FROM products WHERE sku = 'DEMO-SKU-003'), 9, 0, 0);

COMMIT;
