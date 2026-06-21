-- Add the missing lifecycle timestamp without a volatile default table rewrite.
ALTER TABLE inventory_items ADD COLUMN created_at TIMESTAMPTZ;

UPDATE inventory_items
SET created_at = updated_at
WHERE created_at IS NULL;

ALTER TABLE inventory_items
  ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP,
  ALTER COLUMN created_at SET NOT NULL;
