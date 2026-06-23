test "migrate" "latest_schema_applies" {
  migrate {
    to = "__LATEST_MIGRATION__"
  }
}

test "migrate" "checkout_total_amount_check_rejects_inconsistent_amount" {
  migrate {
    to = "__LATEST_MIGRATION__"
  }

  # 前提: customer_id = 100 が存在する。
  # 期待: subtotal + shipping + tax = 115.00 と異なる total_amount = 114.00 は
  # orders_check CHECK 制約により INSERT できない。
  exec {
    sql = <<-SQL
      INSERT INTO customers (id, name, email)
      OVERRIDING SYSTEM VALUE
      VALUES (100, 'Checkout Test Customer', 'total-check@example.invalid');
    SQL
  }
  catch {
    sql = <<-SQL
      INSERT INTO orders (
        order_number,
        customer_id,
        subtotal_amount,
        shipping_fee_amount,
        tax_amount,
        total_amount
      )
      VALUES ('TEST-INVALID-TOTAL', 100, 100.00, 10.00, 5.00, 114.00);
    SQL
  }
  assert {
    sql = <<-SQL
      SELECT count(*) = 0
      FROM orders
      WHERE order_number = 'TEST-INVALID-TOTAL';
    SQL
    error_message = "inconsistent order total must not be persisted"
  }
}

test "migrate" "checkout_conditional_reservation_update_prevents_oversell" {
  migrate {
    to = "__LATEST_MIGRATION__"
  }

  # 前提: product_id = 1001 は available = 5、reserved = 3 で、販売可能数は 2。
  # 期待: 3 個の追加引当は条件付き UPDATE が 0 件となり、reserved_quantity は 3 のまま。
  # 同じ条件式を各 checkout が 1 文で使うことで、先行 checkout 後の後続 checkout は
  # 在庫を超えて更新できない。
  exec {
    sql = <<-SQL
      INSERT INTO products (id, sku, name, status, price_amount, currency)
      OVERRIDING SYSTEM VALUE
      VALUES (1001, 'TEST-CONDITIONAL-UPDATE', 'Conditional reservation test product', 'active', 100.00, 'JPY');

      INSERT INTO inventory_items (product_id, available_quantity, reserved_quantity, reorder_threshold)
      VALUES (1001, 5, 3, 0);
    SQL
  }
  assert {
    sql = <<-SQL
      WITH attempted_reservation AS (
        UPDATE inventory_items
           SET reserved_quantity = reserved_quantity + 3
         WHERE product_id = 1001
           AND available_quantity - reserved_quantity >= 3
        RETURNING product_id
      )
      SELECT
        (SELECT count(*) FROM attempted_reservation) = 0
        AND (SELECT reserved_quantity FROM inventory_items WHERE product_id = 1001) = 3;
    SQL
    error_message = "an over-capacity reservation must update zero rows and preserve inventory"
  }
}

test "migrate" "inventory_quantity_check_rejects_reserved_above_available" {
  migrate {
    to = "__LATEST_MIGRATION__"
  }

  # 前提: product_id = 1002 は available = 5、reserved = 2。
  # 期待: reserved_quantity を 6 にする操作は available_quantity >= reserved_quantity
  # CHECK 制約で拒否され、元の値は変わらない。
  exec {
    sql = <<-SQL
      INSERT INTO products (id, sku, name, status, price_amount, currency)
      OVERRIDING SYSTEM VALUE
      VALUES (1002, 'TEST-INVENTORY-BOUND', 'Inventory bound test product', 'active', 100.00, 'JPY');

      INSERT INTO inventory_items (product_id, available_quantity, reserved_quantity, reorder_threshold)
      VALUES (1002, 5, 2, 0);
    SQL
  }
  catch {
    sql = <<-SQL
      UPDATE inventory_items
         SET reserved_quantity = 6
       WHERE product_id = 1002;
    SQL
  }
  assert {
    sql = <<-SQL
      SELECT available_quantity = 5 AND reserved_quantity = 2
      FROM inventory_items
      WHERE product_id = 1002;
    SQL
    error_message = "rejected inventory update must leave the quantities unchanged"
  }
}

test "migrate" "checkout_cancel_and_shipment_apply_inventory_transitions" {
  migrate {
    to = "__LATEST_MIGRATION__"
  }

  # 前提: product_id = 1003 は available = 10、reserved = 3、product_id = 1004 は
  # available = 10、reserved = 4。各注文には対応する reserved reservation が 1 件ある。
  # 期待: 取消は product_id = 1003 の reserved だけを 0 に戻し、出荷は product_id = 1004 の
  # available / reserved をそれぞれ 6 / 0 に減らして reservation の状態も遷移させる。
  exec {
    sql = <<-SQL
      INSERT INTO customers (id, name, email)
      OVERRIDING SYSTEM VALUE
      VALUES (100, 'Checkout Test Customer', 'lifecycle@example.invalid');

      INSERT INTO products (id, sku, name, status, price_amount, currency)
      OVERRIDING SYSTEM VALUE
      VALUES
        (1003, 'TEST-RELEASE', 'Release test product', 'active', 100.00, 'JPY'),
        (1004, 'TEST-CONSUME', 'Consume test product', 'active', 100.00, 'JPY');

      INSERT INTO inventory_items (product_id, available_quantity, reserved_quantity, reorder_threshold)
      VALUES
        (1003, 10, 3, 0),
        (1004, 10, 4, 0);
    SQL
  }
  exec {
    sql = <<-SQL
      INSERT INTO orders (
        id,
        order_number,
        customer_id,
        subtotal_amount,
        shipping_fee_amount,
        tax_amount,
        total_amount
      )
      OVERRIDING SYSTEM VALUE
      VALUES
        (4001, 'TEST-CANCEL-ORDER', 100, 100.00, 0.00, 0.00, 100.00),
        (4002, 'TEST-SHIP-ORDER', 100, 100.00, 0.00, 0.00, 100.00);

      INSERT INTO inventory_reservations (order_id, product_id, quantity, status)
      VALUES
        (4001, 1003, 3, 'reserved'),
        (4002, 1004, 4, 'reserved');
    SQL
  }
  exec {
    sql = <<-SQL
      -- 取消: 引当だけを戻し、販売可能総数は変えない。
      UPDATE inventory_items AS item
         SET reserved_quantity = item.reserved_quantity - reservation.quantity
        FROM inventory_reservations AS reservation
       WHERE reservation.order_id = 4001
         AND reservation.status = 'reserved'
         AND item.product_id = reservation.product_id;

      UPDATE inventory_reservations
         SET status = 'released'
       WHERE order_id = 4001 AND status = 'reserved';

      UPDATE orders
         SET status = 'canceled'
       WHERE id = 4001;

      INSERT INTO inventory_movements (product_id, order_id, movement_type, quantity_delta, reason)
      VALUES (1003, 4001, 'release', 3, 'test cancellation');

      -- 出荷: available_quantity と reserved_quantity を同量だけ減らす。
      -- orders / shipments の状態遷移は既存設計で別処理に委ねるため、この在庫遷移テストでは扱わない。
      UPDATE inventory_items AS item
         SET available_quantity = item.available_quantity - reservation.quantity,
             reserved_quantity = item.reserved_quantity - reservation.quantity
        FROM inventory_reservations AS reservation
       WHERE reservation.order_id = 4002
         AND reservation.status = 'reserved'
         AND item.product_id = reservation.product_id;

      UPDATE inventory_reservations
         SET status = 'consumed'
       WHERE order_id = 4002 AND status = 'reserved';

      INSERT INTO inventory_movements (product_id, order_id, movement_type, quantity_delta, reason)
      VALUES (1004, 4002, 'ship', -4, 'test shipment');
    SQL
  }
  assert {
    sql = <<-SQL
      SELECT
        (SELECT available_quantity = 10 AND reserved_quantity = 0
           FROM inventory_items WHERE product_id = 1003)
        AND (SELECT status = 'canceled' FROM orders WHERE id = 4001)
        AND (SELECT status = 'released' FROM inventory_reservations WHERE order_id = 4001 AND product_id = 1003)
        AND (SELECT quantity_delta = 3
               FROM inventory_movements
              WHERE order_id = 4001 AND product_id = 1003 AND movement_type = 'release')
        AND (SELECT available_quantity = 6 AND reserved_quantity = 0
           FROM inventory_items WHERE product_id = 1004)
        AND (SELECT status = 'consumed' FROM inventory_reservations WHERE order_id = 4002 AND product_id = 1004)
        AND (SELECT quantity_delta = -4
               FROM inventory_movements
              WHERE order_id = 4002 AND product_id = 1004 AND movement_type = 'ship');
    SQL
    error_message = "cancel and shipment inventory transitions must preserve checkout quantities"
  }
}
