# ==============================================================================
# File: ssl.tf
# Tier: Step 7 - Domain & SSL Certificate Management (AWS ACM)
# Description: Requests an AWS Certificate Manager (ACM) public TLS/SSL certificate
#              for the custom domain and provisions the ALB HTTPS:443 listener.
# ==============================================================================

# ==============================================================================
# 🏢 PROFESSIONAL PRODUCTION SETUP:
# In an enterprise setup with an Application Load Balancer, AWS Certificate Manager
# (ACM) provisions a free managed SSL certificate that binds to the ALB HTTPS:443 listener.
#
# 💡 STANDALONE / BUDGET MODE:
# AWS ACM certificates CANNOT be attached directly to an EC2 instance (ACM only works
# on ALB, CloudFront, or API Gateway).
# Therefore, ACM certificate and validation resources are COMMENTED OUT.
# For standalone EC2, free SSL is installed directly inside the instance via Certbot
# (Let's Encrypt) in install.sh.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Request Public ACM SSL Certificate [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_acm_certificate" "cert" {
#   domain_name       = var.domain_name
#   validation_method = "DNS"
#
#   lifecycle {
#     create_before_destroy = true
#   }
#
#   tags = {
#     Name = "${var.project_name}-acm-certificate"
#   }
# }

# ------------------------------------------------------------------------------
# 2. Wait for ACM Certificate Validation [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_acm_certificate_validation" "cert" {
#   certificate_arn = aws_acm_certificate.cert.arn
# }

# ------------------------------------------------------------------------------
# 3. ALB HTTPS (Port 443) Ingress Listener [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.web.arn
#   }
# }
