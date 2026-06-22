-- checkout_place_order
--
-- docs/ecommerce-checkout.md の checkout 境界を、Aurora PostgreSQL-compatible (PG16) の
-- 単一トランザクション関数として実装する。Aurora を source of truth とし、checkout を
-- この関数呼び出し 1 回で直列化する。
--
-- 振る舞い:
--   1. customers の状態を確認する（active のみ）。
--   2. 決済 authorization 結果を確認する。authorized 以外なら注文を作らず例外で rollback する
--      （docs の「注文作成前に失敗させる」を採用）。
--   3. products / inventory_items を読み、販売状態・通貨・価格を再確認する。
--      expected_unit_price が渡され現在価格と異なる場合は失敗させる。
--   4. orders / order_addresses / order_items を注文時点 snapshot として作成する。
--   5. 在庫引当は oversell しない単一 UPDATE で行う。
--      available_quantity - reserved_quantity >= quantity を条件にし、更新 0 件なら在庫不足で rollback する。
--   6. inventory_reservations / inventory_movements を記録する。
--   7. payments / payment_events に authorization を記録する。
--
-- 引数:
--   p_customer_id            BIGINT       注文する顧客。
--   p_order_number           TEXT         外部向け注文番号（orders.order_number, UNIQUE）。
--   p_currency               CHAR(3)      注文通貨。各 product.currency と一致する必要がある。
--   p_shipping_fee_amount    NUMERIC      送料。NULL は 0 として扱う。
--   p_tax_amount             NUMERIC      税額。NULL は 0 として扱う。
--   p_items                  JSONB        明細配列。1 product につき 1 要素にする（カートで集約済み前提）。
--                                         [{"product_id":1,"quantity":2,"expected_unit_price":1980.00}, ...]
--                                         expected_unit_price は任意。価格変更検知に使う。
--   p_addresses              JSONB        住所 snapshot 配列。
--                                         [{"address_type":"shipping","recipient_name":"...","postal_code":"...",
--                                           "region":"...","city":"...","address_line1":"...",
--                                           "address_line2":"...","phone_number":"..."}, ...]
--   p_payment                JSONB        決済結果。
--                                         {"provider":"stripe","provider_payment_id":"pi_x","status":"authorized",
--                                          "amount":4060.00,"authorized_at":"2026-06-22T00:00:00Z",
--                                          "provider_event_id":"evt_x","raw_event":{...}}
--   p_reservation_expires_at TIMESTAMPTZ  引当の期限。NULL 可。
--
-- 戻り値: 作成した orders.id。
--
-- 注: order の status は authorization 後も 'placed' のままにする。capture 後の 'paid' 遷移は
--     この関数の対象外（別処理）。同一 product を複数明細に分けて渡すと
--     inventory_reservations の UNIQUE(order_id, product_id) で失敗するため、明細は product 単位に集約する。

CREATE OR REPLACE FUNCTION checkout_place_order(
    p_customer_id            BIGINT,
    p_order_number           TEXT,
    p_currency               CHAR(3),
    p_shipping_fee_amount    NUMERIC(12, 2),
    p_tax_amount             NUMERIC(12, 2),
    p_items                  JSONB,
    p_addresses              JSONB,
    p_payment                JSONB,
    p_reservation_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id         BIGINT;
    v_subtotal         NUMERIC(12, 2) := 0;
    v_shipping_fee     NUMERIC(12, 2) := COALESCE(p_shipping_fee_amount, 0);
    v_tax              NUMERIC(12, 2) := COALESCE(p_tax_amount, 0);
    v_total            NUMERIC(12, 2);
    v_lines            JSONB := '[]'::jsonb;
    v_item             JSONB;
    v_product_id       BIGINT;
    v_quantity         INTEGER;
    v_expected_price   NUMERIC(12, 2);
    v_product          products%ROWTYPE;
    v_line_total       NUMERIC(12, 2);
    v_reserved_rows    INTEGER;
    v_addr             JSONB;
    v_payment_status   TEXT;
    v_payment_amount   NUMERIC(12, 2);
    v_payment_id       BIGINT;
BEGIN
    -- 1. 顧客の存在と販売可能状態を確認する。
    PERFORM 1 FROM customers WHERE id = p_customer_id AND status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'checkout_failed: customer % is not active or does not exist', p_customer_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2. 決済 authorization の成否を先に確認する。失敗時は注文を作らず rollback する。
    v_payment_status := p_payment ->> 'status';
    IF NULLIF(BTRIM(p_payment ->> 'provider'), '') IS NULL
       OR NULLIF(BTRIM(p_payment ->> 'provider_payment_id'), '') IS NULL THEN
        RAISE EXCEPTION 'checkout_failed: payment.provider and payment.provider_payment_id are required';
    END IF;
    IF v_payment_status IS DISTINCT FROM 'authorized' THEN
        RAISE EXCEPTION 'checkout_failed: payment authorization was not successful (status=%)',
            COALESCE(v_payment_status, '<null>')
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3. 明細ごとに product / 在庫を再確認し、注文時点 snapshot を組み立てる。
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb))
    LOOP
        v_product_id     := (v_item ->> 'product_id')::BIGINT;
        v_quantity       := (v_item ->> 'quantity')::INTEGER;
        v_expected_price := NULLIF(v_item ->> 'expected_unit_price', '')::NUMERIC(12, 2);

        IF v_product_id IS NULL OR v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION 'checkout_failed: invalid line (product_id=%, quantity=%)',
                v_product_id, v_quantity;
        END IF;

        SELECT * INTO v_product FROM products WHERE id = v_product_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'checkout_failed: product % does not exist', v_product_id;
        END IF;

        -- 販売状態の再確認。
        IF v_product.status <> 'active' THEN
            RAISE EXCEPTION 'checkout_failed: product % is not active (status=%)',
                v_product_id, v_product.status
                USING ERRCODE = 'check_violation';
        END IF;

        -- 通貨の整合性。
        IF v_product.currency <> p_currency THEN
            RAISE EXCEPTION 'checkout_failed: product % currency % differs from order currency %',
                v_product_id, v_product.currency, p_currency
                USING ERRCODE = 'check_violation';
        END IF;

        -- 価格変更の検知（カート時点の価格が渡された場合）。
        IF v_expected_price IS NOT NULL AND v_expected_price <> v_product.price_amount THEN
            RAISE EXCEPTION 'checkout_failed: product % price changed (cart=%, current=%)',
                v_product_id, v_expected_price, v_product.price_amount
                USING ERRCODE = 'check_violation';
        END IF;

        v_line_total := v_product.price_amount * v_quantity;
        v_subtotal   := v_subtotal + v_line_total;

        v_lines := v_lines || jsonb_build_object(
            'product_id',        v_product_id,
            'sku',               v_product.sku,
            'product_name',      v_product.name,
            'unit_price_amount', v_product.price_amount,
            'quantity',          v_quantity,
            'line_total_amount', v_line_total
        );
    END LOOP;

    IF jsonb_array_length(v_lines) = 0 THEN
        RAISE EXCEPTION 'checkout_failed: order has no items';
    END IF;

    -- 決済金額と注文合計の整合性（金額が渡された場合）。
    v_total          := v_subtotal + v_shipping_fee + v_tax;
    v_payment_amount := NULLIF(p_payment ->> 'amount', '')::NUMERIC(12, 2);
    IF v_payment_amount IS NOT NULL AND v_payment_amount <> v_total THEN
        RAISE EXCEPTION 'checkout_failed: payment amount % differs from order total %',
            v_payment_amount, v_total
            USING ERRCODE = 'check_violation';
    END IF;

    -- 4. 注文 header を作成する。
    INSERT INTO orders (
        order_number, customer_id, status, currency,
        subtotal_amount, shipping_fee_amount, tax_amount, total_amount
    )
    VALUES (
        p_order_number, p_customer_id, 'placed', p_currency,
        v_subtotal, v_shipping_fee, v_tax, v_total
    )
    RETURNING id INTO v_order_id;

    INSERT INTO order_status_events (order_id, from_status, to_status, reason)
    VALUES (v_order_id, NULL, 'placed', 'checkout');

    -- 住所 snapshot。
    FOR v_addr IN SELECT * FROM jsonb_array_elements(COALESCE(p_addresses, '[]'::jsonb))
    LOOP
        INSERT INTO order_addresses (
            order_id, address_type, recipient_name, postal_code,
            region, city, address_line1, address_line2, phone_number
        )
        VALUES (
            v_order_id,
            v_addr ->> 'address_type',
            v_addr ->> 'recipient_name',
            v_addr ->> 'postal_code',
            v_addr ->> 'region',
            v_addr ->> 'city',
            v_addr ->> 'address_line1',
            NULLIF(v_addr ->> 'address_line2', ''),
            NULLIF(v_addr ->> 'phone_number', '')
        );
    END LOOP;

    -- 5-6. 明細 snapshot 作成 + 在庫引当 + 引当/監査記録。
    -- inventory_items の行 lock 順を product_id 昇順に固定し、並行 checkout 間の
    -- deadlock を避ける（inventory_release_order / inventory_consume_order も同順）。
    FOR v_item IN
        SELECT e.value
          FROM jsonb_array_elements(v_lines) AS e(value)
         ORDER BY (e.value ->> 'product_id')::BIGINT
    LOOP
        v_product_id := (v_item ->> 'product_id')::BIGINT;
        v_quantity   := (v_item ->> 'quantity')::INTEGER;

        INSERT INTO order_items (
            order_id, product_id, sku, product_name,
            unit_price_amount, quantity, line_total_amount
        )
        VALUES (
            v_order_id,
            v_product_id,
            v_item ->> 'sku',
            v_item ->> 'product_name',
            (v_item ->> 'unit_price_amount')::NUMERIC(12, 2),
            v_quantity,
            (v_item ->> 'line_total_amount')::NUMERIC(12, 2)
        );

        -- oversell を防ぐ単一 UPDATE。read と write の間に別 checkout が割り込んでも、
        -- 行 lock により available - reserved >= quantity を満たした 1 件だけが更新される。
        UPDATE inventory_items
           SET reserved_quantity = reserved_quantity + v_quantity,
               updated_at        = CURRENT_TIMESTAMP
         WHERE product_id = v_product_id
           AND available_quantity - reserved_quantity >= v_quantity;

        GET DIAGNOSTICS v_reserved_rows = ROW_COUNT;
        IF v_reserved_rows = 0 THEN
            RAISE EXCEPTION 'checkout_failed: insufficient stock for product % (requested %)',
                v_product_id, v_quantity
                USING ERRCODE = 'check_violation';
        END IF;

        INSERT INTO inventory_reservations (order_id, product_id, quantity, status, expires_at)
        VALUES (v_order_id, v_product_id, v_quantity, 'reserved', p_reservation_expires_at);

        -- quantity_delta は「販売可能数（available - reserved）への符号付き増減」を表す。
        -- 引当は販売可能数を減らすため負値。
        INSERT INTO inventory_movements (product_id, order_id, movement_type, quantity_delta, reason)
        VALUES (v_product_id, v_order_id, 'reserve', -v_quantity, 'checkout reserve');
    END LOOP;

    -- 7. 決済 authorization を記録する。
    INSERT INTO payments (
        order_id, provider, provider_payment_id, status, amount, currency, authorized_at
    )
    VALUES (
        v_order_id,
        p_payment ->> 'provider',
        p_payment ->> 'provider_payment_id',
        'authorized',
        COALESCE(v_payment_amount, v_total),
        p_currency,
        COALESCE(NULLIF(p_payment ->> 'authorized_at', '')::TIMESTAMPTZ, CURRENT_TIMESTAMP)
    )
    RETURNING id INTO v_payment_id;

    INSERT INTO payment_events (
        payment_id, event_type, provider_event_id, amount, currency, raw_event
    )
    VALUES (
        v_payment_id,
        'authorized',
        NULLIF(p_payment ->> 'provider_event_id', ''),
        COALESCE(v_payment_amount, v_total),
        p_currency,
        p_payment -> 'raw_event'
    );

    RETURN v_order_id;
END;
$$;
