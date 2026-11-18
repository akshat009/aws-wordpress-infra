# ==============================================================================
# File: ssl.tf
# Tier: Domain & SSL (AWS Certificate Manager)
# Description: ACM public certificate + ALB HTTPS:443 listener (TLS 1.3).
#
# ACM certificates only attach to ALB / CloudFront / API Gateway, not to a
# plain EC2. In standalone mode SSL comes from Let's Encrypt instead
# (.github/workflows/install-ssl.yml runs Certbot through SSM).
#
# Two-stage flow (avoids the apply hanging on DNS validation, see notes/15):
#   "migrating"  -> certificate requested; add the CNAME from the
#                   acm_dns_validation_records output to your DNS provider.
#   "enterprise" -> validation completes quickly, HTTPS listener created.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Public ACM certificate (requested in "migrating" and "enterprise")
# ------------------------------------------------------------------------------
resource "aws_acm_certificate" "cert" {
  count = local.request_certificate ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-acm-certificate"
  }
}

# ------------------------------------------------------------------------------
# 2. Wait for DNS validation (only in "enterprise", when the ALB needs it)
# ------------------------------------------------------------------------------
resource "aws_acm_certificate_validation" "cert" {
  count = local.run_alb ? 1 : 0

  certificate_arn = aws_acm_certificate.cert[0].arn

  timeouts {
    create = "15m" # Fail fast with a clear error instead of hanging for 75 minutes
  }
}

# ------------------------------------------------------------------------------
# 3. ALB HTTPS:443 listener with a TLS 1.3 policy
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  count = local.run_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.cert[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web[0].arn
  }
}
