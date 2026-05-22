# ---- Jobs Table (with DynamoDB Streams) ----
resource "aws_dynamodb_table" "jobs" {
  name             = "vto-jobs"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }

  server_side_encryption {
    enabled = true # AWS-managed key
  }

  tags = { Project = var.project }
}

# ---- WebSocket Connections Table ----
resource "aws_dynamodb_table" "connections" {
  name         = "vto-connections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "connection_id"

  attribute {
    name = "connection_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Project = var.project }
}

# ---- Products Catalog Table ----
resource "aws_dynamodb_table" "products" {
  name         = "vto-products"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "product_id"

  attribute {
    name = "product_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Project = var.project }
}

# ---- Models Catalog Table ----
resource "aws_dynamodb_table" "models" {
  name         = "vto-models"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "model_id"

  attribute {
    name = "model_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Project = var.project }
}
