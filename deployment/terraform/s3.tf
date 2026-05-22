# ---- Access Logs Bucket ----
resource "aws_s3_bucket" "access_logs" {
  bucket        = "vto-access-logs-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "access_logs_ssl" {
  bucket = aws_s3_bucket.access_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonSSL"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = ["${aws_s3_bucket.access_logs.arn}", "${aws_s3_bucket.access_logs.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# Allow S3 to write access logs to this bucket
resource "aws_s3_bucket_acl" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  acl    = "log-delivery-write"
  depends_on = [aws_s3_bucket_ownership_controls.access_logs]
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# ---- Main VTO Bucket ----
resource "aws_s3_bucket" "vto" {
  bucket        = "vto-demo-bucket-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "vto" {
  bucket = aws_s3_bucket.vto.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vto" {
  bucket = aws_s3_bucket.vto.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vto" {
  bucket                  = aws_s3_bucket.vto.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "vto" {
  bucket        = aws_s3_bucket.vto.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "access-logs/"
  depends_on    = [aws_s3_bucket_acl.access_logs]
}

resource "aws_s3_bucket_cors_configuration" "vto" {
  bucket = aws_s3_bucket.vto.id
  cors_rule {
    allowed_methods = ["GET", "POST", "PUT"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "vto_ssl" {
  bucket = aws_s3_bucket.vto.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonSSL"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = ["${aws_s3_bucket.vto.arn}", "${aws_s3_bucket.vto.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# ---- S3 → SQS Event Notifications ----
resource "aws_s3_bucket_notification" "vto" {
  bucket = aws_s3_bucket.vto.id

  queue {
    id            = "results-notification"
    queue_arn     = aws_sqs_queue.results.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "results/"
  }

  queue {
    id            = "products-notification"
    queue_arn     = aws_sqs_queue.products.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "products/"
  }

  queue {
    id            = "models-notification"
    queue_arn     = aws_sqs_queue.models.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "models/"
  }

  depends_on = [
    aws_sqs_queue_policy.results,
    aws_sqs_queue_policy.products,
    aws_sqs_queue_policy.models,
  ]
}

# ---- CloudTrail Bucket ----
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "vto-cloudtrail-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "cloudtrail" {
  bucket        = aws_s3_bucket.cloudtrail.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "cloudtrail-access-logs/"
  depends_on    = [aws_s3_bucket_acl.access_logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "DeleteOldLogs"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["${aws_s3_bucket.cloudtrail.arn}", "${aws_s3_bucket.cloudtrail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}
