-- Modify "orders" table
ALTER TABLE "orders" ADD CONSTRAINT "orders_check" CHECK (total_amount = ((subtotal_amount + shipping_fee_amount) + tax_amount)) NOT VALID;
