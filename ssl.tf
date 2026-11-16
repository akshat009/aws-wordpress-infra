# ==============================================================================
# File: ssl.tf
# Tier: Step 7 - Domain & SSL Certificate Management (AWS ACM)
# Description: Requests an AWS Certificate Manager (ACM) public TLS/SSL certificate
#              for the custom domain and outputs DNS validation records for Hostinger.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Request Public ACM SSL Certificate
# ------------------------------------------------------------------------------
# AWS Certificate Manager provides free, automatically renewed SSL certificates.
# DNS validation proves domain ownership by adding a specific CNAME record in Hostinger.
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-acm-certificate"
  }
}
