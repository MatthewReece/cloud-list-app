# --------------------------------------------
# DynamoDB Table for User Shopping Lists
# --------------------------------------------
resource "aws_dynamodb_table" "shopping_list" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # on-demand
  hash_key     = "userId"
  range_key    = "itemId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "itemId"
    type = "S"
  }

  # TTL to auto-delete old items
  ttl {
    attribute_name = "expireAt"
    enabled        = true
  }

  # Point-in-time recovery (PITR) for safety
  point_in_time_recovery {
    enabled = false
  }

  # --------------------------------------------
  # Tags (consistent with other resources)
  # --------------------------------------------
  tags = {
    Project     = "CloudListApp"
    Environment = "Dev"
    ManagedBy   = "Terraform"
  }
}
