-- inventory_consume_order
--
-- 出荷時の在庫消費。docs/ecommerce-checkout.md「在庫引当」節の
-- 「出荷時: available_quantity と reserved_quantity を減らし、inventory_reservations.status を consumed にする」に準拠する。
--
-- 振る舞い（単一トランザクション）:
--   status = 'reserved' の inventory_reservations について
--     - inventory_items.available_quantity と reserved_quantity を同量だけ減らす。
--     - reservation.status を 'consumed' にする。
--     - inventory_movements に 'ship' を記録する。
--
-- 在庫の消費だけを扱い、orders / shipments の状態遷移は別処理に委ねる
-- （docs の event table の責務分離に従う）。
--
-- 引数:
--   p_order_id BIGINT  出荷対象の注文。
--   p_reason   TEXT    出荷理由（movement に残す）。
--
-- 戻り値: 消費した reservation の件数。

CREATE OR REPLACE FUNCTION inventory_consume_order(
    p_order_id BIGINT,
    p_reason   TEXT DEFAULT 'order shipped'
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_res   inventory_reservations%ROWTYPE;
    v_count INTEGER := 0;
BEGIN
    PERFORM 1 FROM orders WHERE id = p_order_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'consume_failed: order % does not exist', p_order_id;
    END IF;

    -- inventory_items の行 lock 順を product_id 昇順に固定し、checkout / release と
    -- 順序を揃えて deadlock を避ける。
    FOR v_res IN
        SELECT * FROM inventory_reservations
         WHERE order_id = p_order_id AND status = 'reserved'
         ORDER BY product_id
         FOR UPDATE
    LOOP
        UPDATE inventory_items
           SET available_quantity = available_quantity - v_res.quantity,
               reserved_quantity  = reserved_quantity - v_res.quantity,
               updated_at         = CURRENT_TIMESTAMP
         WHERE product_id = v_res.product_id;

        UPDATE inventory_reservations
           SET status     = 'consumed',
               updated_at = CURRENT_TIMESTAMP
         WHERE id = v_res.id;

        -- 出荷は在庫が出ていくため販売可能数への符号は負値。
        INSERT INTO inventory_movements (product_id, order_id, movement_type, quantity_delta, reason)
        VALUES (v_res.product_id, p_order_id, 'ship', -v_res.quantity, p_reason);

        v_count := v_count + 1;
    END LOOP;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'consume_failed: order % has no reserved inventory to consume', p_order_id
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN v_count;
END;
$$;
