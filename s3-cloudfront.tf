# ==============================================================================
# File: s3-cloudfront.tf
# Tier: Object Storage & CDN (always on, every mode)
# Description: 1) Private S3 media bucket + CloudFront CDN with Origin Access
#                 Control (WordPress uploads via WP Offload Media).
#              2) Private S3 artifacts bucket holding app releases (wp-content)
#                 so new Auto Scaling servers get the theme/plugins at boot.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Caller Identity Lookup (account ID for globally unique bucket names)
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# ==============================================================================
# MEDIA BUCKET + CLOUDFRONT
# ==============================================================================

# ------------------------------------------------------------------------------
# 2. S3 Media Bucket
# ------------------------------------------------------------------------------
# Servers are disposable; uploads must live outside them.
resource "aws_s3_bucket" "media" {
  bucket        = "${var.project_name}-media-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Name = "${var.project_name}-media-bucket"
  }
}

# ------------------------------------------------------------------------------
# 3. Block all direct public access (only CloudFront can read)
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# 4. Encryption at rest
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ------------------------------------------------------------------------------
# 5. Versioning + lifecycle (recover overwritten or deleted media)
# ------------------------------------------------------------------------------
# A deleted or overwritten file stays recoverable for 30 days, then the old
# version is removed so storage cost doesn't grow forever.
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.media]
}

# ------------------------------------------------------------------------------
# 6. CORS (browsers loading pages from our domain can fetch fonts/images)
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# ------------------------------------------------------------------------------
# 7. CloudFront Origin Access Control (modern replacement for OAI)
# ------------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${var.project_name}-media-oac"
  description                       = "Origin Access Control for WordPress S3 media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ------------------------------------------------------------------------------
# 8. CloudFront CDN Distribution
# ------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "media" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Global CDN for ${var.project_name} WordPress media uploads"
  default_root_object = ""

  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.media.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.media.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # AWS Managed Cache Policy: Managed-CachingOptimized
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  price_class = "PriceClass_100" # US, Canada, Europe, Asia

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project_name}-media-cdn"
  }
}

# ------------------------------------------------------------------------------
# 9. Bucket policy: only this CloudFront distribution may read objects
# ------------------------------------------------------------------------------
# Note: CloudFront can read EVERY path in this bucket, so never store backups
# or other private files here.
resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.media.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.media.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.media]
}

# ==============================================================================
# ARTIFACTS BUCKET (application releases)
# ==============================================================================
# deploy-app.yml uploads wp-content as:
#   releases/latest.tar.gz              <- new servers download this at boot
#   releases/history/<git-sha>.tar.gz   <- kept 90 days for rollback
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # Only rebuildable release files live here

  tags = {
    Name = "${var.project_name}-artifacts-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-release-history"
    status = "Enabled"

    filter {
      prefix = "releases/history/"
    }

    expiration {
      days = 90
    }
  }

  # Database dumps taken by scripts/migrate-db.sh before every migration
  rule {
    id     = "expire-db-backups"
    status = "Enabled"

    filter {
      prefix = "db-backups/"
    }

    expiration {
      days = var.db_backup_retention_days
    }
  }
}
