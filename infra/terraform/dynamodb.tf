resource "aws_dynamodb_table" "shopping_cart" {
  name                        = "${local.name_prefix}-shopping-cart"
  billing_mode                = var.dynamodb_billing_mode
  hash_key                    = "cart_owner_id"
  range_key                   = "item_id"
  table_class                 = var.dynamodb_table_class
  deletion_protection_enabled = var.dynamodb_deletion_protection_enabled

  attribute {
    name = "cart_owner_id"
    type = "S"
  }

  attribute {
    name = "item_id"
    type = "S"
  }

  ttl {
    attribute_name = var.dynamodb_ttl_attribute_name
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "${local.name_prefix}-shopping-cart"
  }
}

resource "aws_dynamodb_table" "customer_activity" {
  name                        = "${local.name_prefix}-customer-activity"
  billing_mode                = var.dynamodb_billing_mode
  hash_key                    = "customer_or_session_id"
  range_key                   = "occurred_at_event_id"
  table_class                 = var.dynamodb_table_class
  deletion_protection_enabled = var.dynamodb_deletion_protection_enabled

  attribute {
    name = "customer_or_session_id"
    type = "S"
  }

  attribute {
    name = "occurred_at_event_id"
    type = "S"
  }

  ttl {
    attribute_name = var.dynamodb_ttl_attribute_name
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "${local.name_prefix}-customer-activity"
  }
}

resource "aws_dynamodb_table" "order_lookup" {
  name                        = "${local.name_prefix}-order-lookup"
  billing_mode                = var.dynamodb_billing_mode
  hash_key                    = "lookup_key"
  table_class                 = var.dynamodb_table_class
  deletion_protection_enabled = var.dynamodb_deletion_protection_enabled

  attribute {
    name = "lookup_key"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "${local.name_prefix}-order-lookup"
  }
}
