-- inventory_release_order
--
-- 注文取消時の在庫戻し。docs/ecommerce-checkout.md「在庫引当」節の
-- 「注文取消時: reserved_quantity を減らし、inventory_reservations.status を released にする」に準拠する。
--
-- 振る舞い（単一トランザクション）:
--   1. orders を FOR UPDATE で lock し、既に canceled / refunded なら二重取消を防ぐため失敗させる。
--   2. status = 'reserved' の inventory_reservations について
--      - inventory_items.reserved_quantity を減らす（available_quantity は変えない）。
--      - reservation.status を 'released' にする。
--      - inventory_movements に 'release' を記録する。
--   3. orders.status を 'canceled' にし、order_status_events を記録する。
--
-- 引数:
--   p_order_id BIGINT  取消対象の注文。
--   p_reason   TEXT    取消理由（movement / status event に残す）。
--
-- 戻り値: 解放した reservation の件数。

CREATE OR REPLACE FUNCTION inventory_release_order(
    p_order_id BIGINT,
    p_reason   TEXT DEFAULT 'order canceled'
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_res   inventory_reservations%ROWTYPE;
    v_count INTEGER := 0;
BEGIN
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'release_failed: order % does not exist', p_order_id;
    END IF;
    IF v_order.status IN ('canceled', 'refunded') THEN
        RAISE EXCEPTION 'release_failed: order % is already %', p_order_id, v_order.status
            USING ERRCODE = 'check_violation';
    END IF;

    FOR v_res IN
        SELECT * FROM inventory_reservations
         WHERE order_id = p_order_id AND status = 'reserved'
         FOR UPDATE
    LOOP
        UPDATE inventory_items
           SET reserved_quantity = reserved_quantity - v_res.quantity,
               updated_at        = CURRENT_TIMESTAMP
         WHERE product_id = v_res.product_id;

        UPDATE inventory_reservations
           SET status     = 'released',
               updated_at = CURRENT_TIMESTAMP
         WHERE id = v_res.id;

        -- 引当解放は販売可能数を戻すため正値。
        INSERT INTO inventory_movements (product_id, order_id, movement_type, quantity_delta, reason)
        VALUES (v_res.product_id, p_order_id, 'release', v_res.quantity, p_reason);

        v_count := v_count + 1;
    END LOOP;

    UPDATE orders
       SET status     = 'canceled',
           updated_at = CURRENT_TIMESTAMP
     WHERE id = p_order_id;

    INSERT INTO order_status_events (order_id, from_status, to_status, reason)
    VALUES (p_order_id, v_order.status, 'canceled', p_reason);

    RETURN v_count;
END;
$$;
