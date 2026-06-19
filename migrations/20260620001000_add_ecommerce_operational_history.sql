-- Add operational history tables for checkout, inventory, payment, and shipment workflows.
CREATE TABLE order_addresses (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  address_type TEXT NOT NULL CHECK (address_type IN ('shipping', 'billing')),
  recipient_name TEXT NOT NULL,
  postal_code TEXT NOT NULL,
  region TEXT NOT NULL,
  city TEXT NOT NULL,
  address_line1 TEXT NOT NULL,
  address_line2 TEXT,
  phone_number TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (order_id, address_type)
);

CREATE INDEX order_addresses_order_id_idx ON order_addresses (order_id);

CREATE TABLE order_status_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  from_status TEXT,
  to_status TEXT NOT NULL CHECK (to_status IN ('placed', 'paid', 'fulfilled', 'canceled', 'refunded')),
  reason TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX order_status_events_order_id_occurred_at_idx
  ON order_status_events (order_id, occurred_at DESC);

CREATE TABLE inventory_reservations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  product_id BIGINT NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  status TEXT NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved', 'released', 'consumed')),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (order_id, product_id)
);

CREATE INDEX inventory_reservations_product_id_status_idx
  ON inventory_reservations (product_id, status);
CREATE INDEX inventory_reservations_expires_at_idx
  ON inventory_reservations (expires_at)
  WHERE expires_at IS NOT NULL AND status = 'reserved';

CREATE TABLE inventory_movements (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
  order_id BIGINT REFERENCES orders (id) ON DELETE SET NULL,
  movement_type TEXT NOT NULL CHECK (movement_type IN ('stock_in', 'reserve', 'release', 'ship', 'adjust')),
  quantity_delta INTEGER NOT NULL CHECK (quantity_delta <> 0),
  reason TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX inventory_movements_product_id_occurred_at_idx
  ON inventory_movements (product_id, occurred_at DESC);
CREATE INDEX inventory_movements_order_id_idx ON inventory_movements (order_id);

CREATE TABLE payment_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id BIGINT NOT NULL REFERENCES payments (id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('authorized', 'captured', 'failed', 'refunded', 'voided')),
  provider_event_id TEXT,
  amount NUMERIC(12, 2) CHECK (amount >= 0),
  currency CHAR(3) NOT NULL DEFAULT 'JPY',
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  raw_event JSONB,
  UNIQUE (provider_event_id)
);

CREATE INDEX payment_events_payment_id_occurred_at_idx
  ON payment_events (payment_id, occurred_at DESC);

CREATE TABLE shipment_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  shipment_id BIGINT NOT NULL REFERENCES shipments (id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('preparing', 'shipped', 'in_transit', 'delivered', 'returned', 'canceled')),
  location TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  raw_event JSONB
);

CREATE INDEX shipment_events_shipment_id_occurred_at_idx
  ON shipment_events (shipment_id, occurred_at DESC);
