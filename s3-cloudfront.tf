# ==============================================================================
# File: s3-cloudfront.tf
# Tier: Step 5 - S3 Media Storage & CloudFront CDN with Origin Access Control (OAC)
# Description: Provisions a hardened, zero-public-access S3 bucket for WordPress
#              media uploads (/wp-content/uploads), a CloudFront CDN edge distribution,
#              modern Origin Access Control (OAC), and least-privilege bucket policy.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Caller Identity Lookup
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------------------
# 2. S3 Media Bucket (Stateless Compute Decoupling)
# ------------------------------------------------------------------------------
# In a horizontally scaled auto-scaling architecture, EC2 instances are ephemeral.
# If WordPress stores media on local disk, new instances will lack uploaded images.
# This bucket offloads all media attachments permanently into object storage.
resource "aws_s3_bucket" "media" {
  bucket        = "${var.project_name}-media-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Name = "${var.project_name}-media-bucket"
  }
}

# ------------------------------------------------------------------------------
# 3. S3 Public Access Block (Zero Direct Public Ingress)
# ------------------------------------------------------------------------------
# Enforces enterprise security posture: public users CANNOT access S3 directly.
# All public requests MUST be routed through CloudFront CDN with edge caching.
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# 4. S3 Server-Side Encryption (At-Rest Protection)
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
# 5. S3 CORS Configuration (Cross-Origin Asset Sharing)
# ------------------------------------------------------------------------------
# Allows web browsers loading pages from our domain or ALB to fetch fonts/images.
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
# 6. CloudFront Origin Access Control (OAC)
# ------------------------------------------------------------------------------
# Modern AWS standard (replacing legacy Origin Access Identity - OAI).
# Signs requests from CloudFront to S3 using SigV4 and cryptographically verifies
# that only this specific CloudFront distribution can fetch objects from S3.
resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${var.project_name}-media-oac"
  description                       = "Origin Access Control for WordPress S3 media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ------------------------------------------------------------------------------
# 7. CloudFront CDN Distribution (Global Edge Caching)
# ------------------------------------------------------------------------------
# Delivers media assets from 600+ Points of Presence (PoPs) worldwide.
# Reduces latency, eliminates load on EC2/ALB, and dramatically lowers bandwidth costs.
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

    # AWS Managed Cache Policy: Managed-CachingOptimized (ID: 658327ea-f89d-4fab-a63d-7e88639e58f6)
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  price_class = "PriceClass_100" # Cost-effective: US, Canada, Europe, Asia

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
# 8. S3 Bucket Policy (Restricted to CloudFront Distribution)
# ------------------------------------------------------------------------------
# Grants s3:GetObject permission ONLY to the CloudFront distribution via OAC.
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
