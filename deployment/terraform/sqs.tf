# ---- Dead Letter Queues ----
resource "aws_sqs_queue" "results_dlq" {
  name                      = "vto-results-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "results_dlq" {
  queue_url = aws_sqs_queue.results_dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonSSL"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.results_dlq.arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_sqs_queue" "products_dlq" {
  name                      = "vto-products-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "products_dlq" {
  queue_url = aws_sqs_queue.products_dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonSSL"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.products_dlq.arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# ---- Main Queues ----
resource "aws_sqs_queue" "results" {
  name                       = "vto-results-queue"
  visibility_timeout_seconds = 360 # 6 minutes
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.results_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "results" {
  queue_url = aws_sqs_queue.results.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowS3Publish"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.results.arn
        Condition = { ArnLike = { "aws:SourceArn" = aws_s3_bucket.vto.arn } }
      },
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.results.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

resource "aws_sqs_queue" "products" {
  name                       = "vto-products-queue"
  visibility_timeout_seconds = 360
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.products_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "products" {
  queue_url = aws_sqs_queue.products.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowS3Publish"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.products.arn
        Condition = { ArnLike = { "aws:SourceArn" = aws_s3_bucket.vto.arn } }
      },
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.products.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

resource "aws_sqs_queue" "models" {
  name                       = "vto-models-queue"
  visibility_timeout_seconds = 360
  sqs_managed_sse_enabled    = true

  # Reuses products DLQ (same as CDK)
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.products_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "models" {
  queue_url = aws_sqs_queue.models.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowS3Publish"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.models.arn
        Condition = { ArnLike = { "aws:SourceArn" = aws_s3_bucket.vto.arn } }
      },
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.models.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}
