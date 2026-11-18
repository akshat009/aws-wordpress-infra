# ==============================================================================
# File: outputs.tf
# Tier: Return Values
# Description: Resource IDs and endpoints. Mode-specific outputs return null
#              when that part of the architecture is switched off, so this file
#              never needs editing when architecture_mode changes.
# ==============================================================================

# ------------------------------------------------------------------------------
# Architecture
# ------------------------------------------------------------------------------
output "architecture_mode" {
  description = "Which architecture is currently deployed"
  value       = var.architecture_mode
}

output "wordpress_url" {
  description = "Public web URL of the WordPress site"
  value       = "https://${var.domain_name}"
}

# Where traffic actually lands: the Elastic IP in standalone/migrating mode, the
# ALB DNS name in enterprise mode. Used by the pipeline's smoke test.
output "app_endpoint" {
  description = "Elastic IP (standalone/migrating) or ALB DNS name (enterprise)"
  value       = local.run_alb ? one(aws_lb.main[*].dns_name) : one(aws_eip.web[*].public_ip)
}

output "dns_instructions" {
  description = "What the Hostinger DNS record for the site should be right now"
  value = local.run_alb ? (
    "CNAME  ${split(".", var.domain_name)[0]}  ->  ${one(aws_lb.main[*].dns_name)}"
    ) : (
    "A  ${split(".", var.domain_name)[0]}  ->  ${one(aws_eip.web[*].public_ip)}"
  )
}

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the custom VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "Primary IPv4 CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB and web servers)"
  value       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs (RDS and Redis)"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.gw.id
}

# ------------------------------------------------------------------------------
# Security Groups
# ------------------------------------------------------------------------------
output "alb_security_group_id" {
  description = "Security group ID of the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "web_security_group_id" {
  description = "Security group ID of the WordPress servers"
  value       = aws_security_group.web.id
}

output "db_security_group_id" {
  description = "Security group ID of Amazon RDS MySQL"
  value       = aws_security_group.db.id
}

output "redis_security_group_id" {
  description = "Security group ID reserved for ElastiCache Redis"
  value       = aws_security_group.redis.id
}

# ------------------------------------------------------------------------------
# IAM
# ------------------------------------------------------------------------------
output "ec2_iam_role_name" {
  description = "Name of the IAM role used by WordPress servers"
  value       = aws_iam_role.ec2.name
}

output "ec2_iam_role_arn" {
  description = "ARN of the IAM role used by WordPress servers"
  value       = aws_iam_role.ec2.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the instance profile attached to WordPress servers"
  value       = aws_iam_instance_profile.ec2.name
}

output "ec2_instance_profile_arn" {
  description = "ARN of the instance profile attached to WordPress servers"
  value       = aws_iam_instance_profile.ec2.arn
}

# ------------------------------------------------------------------------------
# Secrets (location only - never the value)
# ------------------------------------------------------------------------------
output "db_password_ssm_parameter" {
  description = "SSM Parameter Store name holding the DB password (read with: aws ssm get-parameter --with-decryption)"
  value       = aws_ssm_parameter.db_password.name
}

# ------------------------------------------------------------------------------
# Standalone mode (null in enterprise mode)
# ------------------------------------------------------------------------------
output "wordpress_public_ip" {
  description = "Elastic IP of the standalone server"
  value       = one(aws_eip.web[*].public_ip)
}

output "standalone_instance_id" {
  description = "Instance ID of the standalone server"
  value       = one(aws_instance.web[*].id)
}

# ------------------------------------------------------------------------------
# Database (null in standalone mode)
# ------------------------------------------------------------------------------
output "rds_endpoint" {
  description = "RDS connection endpoint (host:port)"
  value       = one(aws_db_instance.wordpress[*].endpoint)
}

output "rds_address" {
  description = "RDS hostname"
  value       = one(aws_db_instance.wordpress[*].address)
}

# ------------------------------------------------------------------------------
# Enterprise fleet (null unless enterprise mode)
# ------------------------------------------------------------------------------
output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = one(aws_lb.main[*].dns_name)
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = one(aws_lb.main[*].arn)
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = one(aws_lb_target_group.web[*].arn)
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = one(aws_autoscaling_group.web[*].name)
}

# ------------------------------------------------------------------------------
# SSL certificate (migrating + enterprise)
# ------------------------------------------------------------------------------
output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = one(aws_acm_certificate.cert[*].arn)
}

output "acm_dns_validation_records" {
  description = "CNAME record(s) to add in Hostinger so ACM can issue the certificate"
  value = local.request_certificate ? [
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  ] : []
}

# ------------------------------------------------------------------------------
# Storage & CDN
# ------------------------------------------------------------------------------
output "s3_media_bucket_name" {
  description = "Name of the S3 media bucket (enter in WP Offload Media)"
  value       = aws_s3_bucket.media.id
}

output "s3_media_bucket_arn" {
  description = "ARN of the S3 media bucket"
  value       = aws_s3_bucket.media.arn
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.media.id
}

output "cloudfront_distribution_domain_name" {
  description = "CloudFront domain for media (enter in WP Offload Media > Delivery)"
  value       = aws_cloudfront_distribution.media.domain_name
}

output "artifacts_bucket_name" {
  description = "S3 bucket holding app releases (wp-content)"
  value       = aws_s3_bucket.artifacts.id
}

# ------------------------------------------------------------------------------
# Monitoring
# ------------------------------------------------------------------------------
output "alerts_sns_topic_arn" {
  description = "SNS topic receiving all alarms and budget alerts"
  value       = aws_sns_topic.alerts.arn
}
