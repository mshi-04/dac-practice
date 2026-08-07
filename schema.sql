CREATE TABLE customers (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer_addresses (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  recipient_name TEXT NOT NULL,
  postal_code TEXT NOT NULL,
  region TEXT NOT NULL,
  city TEXT NOT NULL,
  address_line1 TEXT NOT NULL,
  address_line2 TEXT,
  phone_number TEXT,
  is_default_shipping BOOLEAN NOT NULL DEFAULT FALSE,
  is_default_billing BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX customer_addresses_customer_id_idx ON customer_addresses (customer_id);
CREATE UNIQUE INDEX customer_addresses_default_shipping_idx
  ON customer_addresses (customer_id)
  WHERE is_default_shipping = TRUE;
CREATE UNIQUE INDEX customer_addresses_default_billing_idx
  ON customer_addresses (customer_id)
  WHERE is_default_billing = TRUE;

CREATE TABLE product_categories (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  parent_category_id BIGINT REFERENCES product_categories (id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX product_categories_parent_category_id_idx ON product_categories (parent_category_id);

CREATE TABLE products (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  category_id BIGINT REFERENCES product_categories (id) ON DELETE SET NULL,
  sku TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'archived')),
  price_amount NUMERIC(12, 2) NOT NULL CHECK (price_amount >= 0),
  currency CHAR(3) NOT NULL DEFAULT 'JPY',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX products_category_id_idx ON products (category_id);
CREATE INDEX products_status_idx ON products (status);

CREATE TABLE inventory_items (
  product_id BIGINT PRIMARY KEY REFERENCES products (id) ON DELETE CASCADE,
  available_quantity INTEGER NOT NULL DEFAULT 0 CHECK (available_quantity >= 0),
  reserved_quantity INTEGER NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0),
  reorder_threshold INTEGER NOT NULL DEFAULT 0 CHECK (reorder_threshold >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (available_quantity >= reserved_quantity)
);

CREATE TABLE orders (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_number TEXT NOT NULL UNIQUE,
  customer_id BIGINT NOT NULL REFERENCES customers (id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'placed' CHECK (status IN ('placed', 'paid', 'fulfilled', 'canceled', 'refunded')),
  currency CHAR(3) NOT NULL DEFAULT 'JPY',
  subtotal_amount NUMERIC(12, 2) NOT NULL CHECK (subtotal_amount >= 0),
  shipping_fee_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (shipping_fee_amount >= 0),
  tax_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  total_amount NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
  placed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (total_amount = subtotal_amount + shipping_fee_amount + tax_amount)
);

CREATE INDEX orders_customer_id_placed_at_idx ON orders (customer_id, placed_at DESC);
CREATE INDEX orders_status_idx ON orders (status);

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

CREATE TABLE order_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  product_id BIGINT REFERENCES products (id) ON DELETE SET NULL,
  sku TEXT NOT NULL,
  product_name TEXT NOT NULL,
  unit_price_amount NUMERIC(12, 2) NOT NULL CHECK (unit_price_amount >= 0),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  line_total_amount NUMERIC(12, 2) NOT NULL CHECK (line_total_amount >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX order_items_order_id_idx ON order_items (order_id);
CREATE INDEX order_items_product_id_idx ON order_items (product_id);

CREATE TABLE order_status_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
  from_status TEXT CHECK (from_status IS NULL OR from_status IN ('placed', 'paid', 'fulfilled', 'canceled', 'refunded')),
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

CREATE TABLE payments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders (id) ON DELETE RESTRICT,
  provider TEXT NOT NULL,
  provider_payment_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'authorized' CHECK (status IN ('authorized', 'captured', 'failed', 'refunded', 'voided')),
  amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
  currency CHAR(3) NOT NULL DEFAULT 'JPY',
  authorized_at TIMESTAMPTZ,
  captured_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (provider, provider_payment_id)
);

CREATE INDEX payments_order_id_idx ON payments (order_id);
CREATE INDEX payments_status_idx ON payments (status);

CREATE TABLE payment_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id BIGINT NOT NULL REFERENCES payments (id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('authorized', 'captured', 'failed', 'refunded', 'voided')),
  provider_event_id TEXT,
  amount NUMERIC(12, 2) CHECK (amount >= 0),
  currency CHAR(3) NOT NULL DEFAULT 'JPY',
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  raw_event JSONB
);

CREATE INDEX payment_events_payment_id_occurred_at_idx
  ON payment_events (payment_id, occurred_at DESC);
CREATE UNIQUE INDEX payment_events_provider_event_id_idx
  ON payment_events (provider_event_id)
  WHERE provider_event_id IS NOT NULL;

CREATE TABLE shipments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders (id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'preparing' CHECK (status IN ('preparing', 'shipped', 'delivered', 'returned', 'canceled')),
  carrier TEXT,
  tracking_number TEXT,
  shipped_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX shipments_order_id_idx ON shipments (order_id);
CREATE UNIQUE INDEX shipments_carrier_tracking_number_idx
  ON shipments (carrier, tracking_number)
  WHERE carrier IS NOT NULL AND tracking_number IS NOT NULL;

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
