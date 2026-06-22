-- ecommerce_local_seed.sql
--
-- ローカル PostgreSQL で商品検索、在庫確認、checkout を試すための seed data。
-- schema.sql / migrations の適用後に実行する。各自然キーで UPSERT するため、再実行しても
-- 重複せず、ここで定義した値に戻る。

\set ON_ERROR_STOP on

BEGIN;

-- 顧客。checkout の検証には active の yuki.sato@example.test を使用する。
INSERT INTO customers (name, email, status)
VALUES
    ('佐藤 優希', 'yuki.sato@example.test', 'active'),
    ('田中 健', 'ken.tanaka@example.test', 'active'),
    ('鈴木 美咲', 'misaki.suzuki@example.test', 'suspended')
ON CONFLICT (email) DO UPDATE
SET name = EXCLUDED.name,
    status = EXCLUDED.status,
    updated_at = CURRENT_TIMESTAMP;

-- カテゴリ。seed 管理対象の親子関係は、全 slug を確定してから設定する。
INSERT INTO product_categories (name, slug, display_order)
VALUES
    ('文具', 'stationery', 10),
    ('飲料', 'beverages', 20),
    ('書籍', 'books', 30),
    ('ノート', 'notebooks', 11),
    ('デスクアクセサリ', 'desk-accessories', 12)
ON CONFLICT (slug) DO UPDATE
SET name = EXCLUDED.name,
    display_order = EXCLUDED.display_order,
    updated_at = CURRENT_TIMESTAMP;

-- seed 管理対象は既存の親子関係を一度消し、下記の定義だけに収束させる。
-- 対象外のカテゴリを更新しないことで、ローカル DB の追加データを壊さない。
UPDATE product_categories
   SET parent_category_id = NULL,
       updated_at = CURRENT_TIMESTAMP
 WHERE slug IN ('stationery', 'beverages', 'books', 'notebooks', 'desk-accessories');

UPDATE product_categories AS child
   SET parent_category_id = parent.id,
       updated_at = CURRENT_TIMESTAMP
  FROM product_categories AS parent
 WHERE (child.slug = 'notebooks' AND parent.slug = 'stationery')
    OR (child.slug = 'desk-accessories' AND parent.slug = 'stationery');

-- 商品。active 以外の状態も含め、販売中商品の絞り込みを確認できるようにする。
WITH seed_products (category_slug, sku, name, description, status, price_amount, currency) AS (
    VALUES
        ('notebooks',        'SEED-NOTEBOOK-A5-001',     'A5 方眼ノート',          '持ち運びやすい A5 サイズ、192 ページの方眼ノート。', 'active',   480.00::NUMERIC, 'JPY'::CHAR(3)),
        ('notebooks',        'SEED-NOTEBOOK-B5-001',     'B5 横罫ノート',          '授業や会議メモ向けの B5 横罫ノート。',              'active',   620.00::NUMERIC, 'JPY'::CHAR(3)),
        ('stationery',       'SEED-PEN-GEL-001',         'ゲルインクペン 0.5mm',   '黒インク、替芯対応。',                                'active',   240.00::NUMERIC, 'JPY'::CHAR(3)),
        ('desk-accessories', 'SEED-KEYBOARD-001',        '静音メカニカルキーボード', 'テンキーレス、日本語配列。',                         'active', 12800.00::NUMERIC, 'JPY'::CHAR(3)),
        ('desk-accessories', 'SEED-MONITOR-STAND-001',   'アルミ製モニタースタンド', '耐荷重 10kg、収納スペース付き。',                    'active',  5980.00::NUMERIC, 'JPY'::CHAR(3)),
        ('beverages',        'SEED-MUG-INSULATED-001',   '真空断熱マグ 350ml',     '保温・保冷対応のステンレスマグ。',                    'active',  2980.00::NUMERIC, 'JPY'::CHAR(3)),
        ('beverages',        'SEED-COFFEE-BLEND-001',    'ドリップコーヒー 10袋',  '中深煎りブレンドの個包装ドリップバッグ。',            'active',   980.00::NUMERIC, 'JPY'::CHAR(3)),
        ('books',            'SEED-BOOK-POSTGRES-001',  'PostgreSQL 実践入門',    'SQL と運用の基礎を扱う技術書。',                       'active',  3600.00::NUMERIC, 'JPY'::CHAR(3)),
        ('stationery',       'SEED-PLANNER-2026-001',    '週間プランナー 2026',    '月曜始まり、年間・月間・週間ページ付き。',            'active',  1680.00::NUMERIC, 'JPY'::CHAR(3)),
        ('books',            'SEED-BOOK-ARCHIVED-001',  '旧版 SQL リファレンス',   '販売終了した旧版。',                                  'archived', 2200.00::NUMERIC, 'JPY'::CHAR(3)),
        ('stationery',       'SEED-PEN-DRAFT-001',       '万年筆インク 黒',         '発売準備中の商品。',                                  'draft',     900.00::NUMERIC, 'JPY'::CHAR(3))
)
INSERT INTO products (category_id, sku, name, description, status, price_amount, currency)
SELECT category.id, product.sku, product.name, product.description,
       product.status, product.price_amount, product.currency
  FROM seed_products AS product
  JOIN product_categories AS category ON category.slug = product.category_slug
ON CONFLICT (sku) DO UPDATE
SET category_id = EXCLUDED.category_id,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    status = EXCLUDED.status,
    price_amount = EXCLUDED.price_amount,
    currency = EXCLUDED.currency,
    updated_at = CURRENT_TIMESTAMP;

-- available_quantity は確保済み在庫を含む物理在庫、reserved_quantity は注文引当数。
WITH seed_inventory (sku, available_quantity, reserved_quantity, reorder_threshold) AS (
    VALUES
        ('SEED-NOTEBOOK-A5-001',   120,  8, 20),
        ('SEED-NOTEBOOK-B5-001',    64,  4, 15),
        ('SEED-PEN-GEL-001',       240, 12, 50),
        ('SEED-KEYBOARD-001',       18,  2,  5),
        ('SEED-MONITOR-STAND-001',  12,  1,  4),
        ('SEED-MUG-INSULATED-001',  36,  3, 10),
        ('SEED-COFFEE-BLEND-001',   80,  0, 20),
        ('SEED-BOOK-POSTGRES-001',  22,  1,  6),
        ('SEED-PLANNER-2026-001',   9,  0,  8),
        ('SEED-BOOK-ARCHIVED-001',  3,  0,  0),
        ('SEED-PEN-DRAFT-001',      0,  0,  0)
)
INSERT INTO inventory_items (product_id, available_quantity, reserved_quantity, reorder_threshold)
SELECT product.id, inventory.available_quantity, inventory.reserved_quantity,
       inventory.reorder_threshold
  FROM seed_inventory AS inventory
  JOIN products AS product ON product.sku = inventory.sku
ON CONFLICT (product_id) DO UPDATE
SET available_quantity = EXCLUDED.available_quantity,
    reserved_quantity = EXCLUDED.reserved_quantity,
    reorder_threshold = EXCLUDED.reorder_threshold,
    updated_at = CURRENT_TIMESTAMP;

COMMIT;
