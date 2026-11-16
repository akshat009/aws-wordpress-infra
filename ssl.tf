# ==============================================================================
# File: ssl.tf
# Tier: Step 7 - Domain & SSL Certificate Management (AWS ACM)
# Description: Requests an AWS Certificate Manager (ACM) public TLS/SSL certificate
#              for the custom domain and provisions the ALB HTTPS:443 listener.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Request Public ACM SSL Certificate
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 2. Wait for ACM Certificate Validation
# ------------------------------------------------------------------------------
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn = aws_acm_certificate.cert.arn
}

# ------------------------------------------------------------------------------
# 3. ALB HTTPS (Port 443) Ingress Listener
# ------------------------------------------------------------------------------
# 💡 NOTE (IF NO LOAD BALANCER): AWS ACM public SSL certificates CANNOT be attached
#    directly to an EC2 instance. ACM only works on ALB, NLB, CloudFront, or API Gateway.
#    If running without an ALB, comment out this entire listener resource and install
#    Certbot (Let's Encrypt) on the EC2 instance (or place CloudFront in front of EC2).
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
