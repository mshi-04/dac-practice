-- inventory_adjust
--
-- 入庫・棚卸・手動調整。docs/ecommerce-checkout.md「在庫引当」節の
-- 「棚卸や手動調整: inventory_movements.movement_type = 'adjust' で理由を残す」と、
-- 入庫（stock_in）を扱う。引当数（reserved_quantity）は変えず、販売可能総数
-- （available_quantity）だけを増減する。
--
-- 引数:
--   p_product_id     BIGINT   対象 product。
--   p_quantity_delta INTEGER  available_quantity への増減（>0 入庫、<0 減算）。0 は不可。
--   p_movement_type  TEXT     'stock_in' または 'adjust'。
--   p_reason         TEXT     監査用の理由。
--
-- 戻り値: なし。
--
-- 注: available_quantity >= reserved_quantity の CHECK 制約があるため、
--     引当済みを下回る減算は制約違反で失敗する（rollback）。

CREATE OR REPLACE FUNCTION inventory_adjust(
    p_product_id     BIGINT,
    p_quantity_delta INTEGER,
    p_movement_type  TEXT DEFAULT 'adjust',
    p_reason         TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_quantity_delta = 0 THEN
        RAISE EXCEPTION 'adjust_failed: quantity_delta must not be zero';
    END IF;
    IF p_movement_type NOT IN ('stock_in', 'adjust') THEN
        RAISE EXCEPTION 'adjust_failed: movement_type must be stock_in or adjust (got %)', p_movement_type;
    END IF;

    UPDATE inventory_items
       SET available_quantity = available_quantity + p_quantity_delta,
           updated_at         = CURRENT_TIMESTAMP
     WHERE product_id = p_product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'adjust_failed: inventory for product % does not exist', p_product_id;
    END IF;

    INSERT INTO inventory_movements (product_id, movement_type, quantity_delta, reason)
    VALUES (p_product_id, p_movement_type, p_quantity_delta, p_reason);
END;
$$;
