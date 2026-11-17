# ==============================================================================
# File: outputs.tf
# Tier: Project Return Values (Outputs)
# Description: Exposes critical resource IDs, endpoints, and attributes.
# ==============================================================================

# ------------------------------------------------------------------------------
# Tier: Step 1 - Networking Return Values
# ------------------------------------------------------------------------------

output "vpc_id" {
  description = "The unique AWS resource identifier of the provisioned custom VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The primary IPv4 address block allocated to the custom VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs"
  value       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

output "private_subnet_ids" {
  description = "List of Private Subnet IDs"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

output "internet_gateway_id" {
  description = "The unique AWS resource identifier of the attached Internet Gateway"
  value       = aws_internet_gateway.gw.id
}

# ------------------------------------------------------------------------------
# Tier: Step 2 - Security Group Return Values
# ------------------------------------------------------------------------------

output "alb_security_group_id" {
  description = "Security group ID attached to the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "web_security_group_id" {
  description = "Security group ID attached to the WordPress EC2 instance"
  value       = aws_security_group.web.id
}

output "db_security_group_id" {
  description = "Security group ID attached to Amazon RDS MySQL"
  value       = aws_security_group.db.id
}

output "redis_security_group_id" {
  description = "Security group ID attached to Amazon ElastiCache Redis"
  value       = aws_security_group.redis.id
}

# ------------------------------------------------------------------------------
# Tier: Step 3 - IAM Return Values
# ------------------------------------------------------------------------------

output "ec2_iam_role_name" {
  description = "Name of the IAM Role attached to WordPress EC2 instance"
  value       = aws_iam_role.ec2.name
}

output "ec2_iam_role_arn" {
  description = "ARN of the IAM Role attached to WordPress EC2 instance"
  value       = aws_iam_role.ec2.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the IAM Instance Profile attached to WordPress instance"
  value       = aws_iam_instance_profile.ec2.name
}

output "ec2_instance_profile_arn" {
  description = "ARN of the IAM Instance Profile attached to WordPress instance"
  value       = aws_iam_instance_profile.ec2.arn
}

# ------------------------------------------------------------------------------
# Tier: Step 4 - Relational Database Return Values [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# ==============================================================================
# 🏢 PROFESSIONAL PRODUCTION SETUP:
# In an enterprise setup, outputs expose the RDS endpoint, address, and credentials
# for downstream microservices, monitoring agents, and CI/CD database migrations.
#
# 💡 STANDALONE / BUDGET MODE:
# Commented out because MySQL runs locally (localhost) inside the standalone EC2.
# ==============================================================================
# output "rds_endpoint" {
#   description = "The connection endpoint for the Amazon RDS MySQL database (Host:Port)"
#   value       = aws_db_instance.wordpress.endpoint
# }
#
# output "rds_address" {
#   description = "The DNS hostname address of the RDS MySQL database"
#   value       = aws_db_instance.wordpress.address
# }
#
# output "rds_port" {
#   description = "The database listening port (default MySQL: 3306)"
#   value       = aws_db_instance.wordpress.port
# }
#
# output "rds_database_name" {
#   description = "The initial MySQL database name"
#   value       = aws_db_instance.wordpress.db_name
# }
#
# output "rds_username" {
#   description = "Master administrative username for database connections"
#   value       = aws_db_instance.wordpress.username
# }

# ------------------------------------------------------------------------------
# Tier: Step 6 - Compute & Application Load Balancer Return Values [COMMENTED OUT]
# ------------------------------------------------------------------------------
# ==============================================================================
# 🏢 PROFESSIONAL PRODUCTION SETUP:
# In an enterprise setup, outputs provide the dynamic ALB DNS endpoint, ARN,
# and Auto Scaling Group name to configure Route 53 Aliases and CI/CD fleet deploys.
#
# 💡 STANDALONE / BUDGET MODE:
# Replaced with the static Elastic IP of the standalone EC2 instance.
# ==============================================================================
# output "alb_dns_name" {
#   description = "The public dynamic DNS endpoint of the Application Load Balancer"
#   value       = aws_lb.main.dns_name
# }
#
# output "alb_arn" {
#   description = "The Amazon Resource Name (ARN) of the Application Load Balancer"
#   value       = aws_lb.main.arn
# }
#
# output "target_group_arn" {
#   description = "The Amazon Resource Name (ARN) of the ALB Target Group"
#   value       = aws_lb_target_group.web.arn
# }
#
# output "autoscaling_group_name" {
#   description = "Name of the Auto Scaling Group managing WordPress web servers"
#   value       = aws_autoscaling_group.web.name
# }

# ------------------------------------------------------------------------------
# Standalone Single-Server Outputs
# ------------------------------------------------------------------------------
output "wordpress_public_ip" {
  description = "Static Elastic IP address of the standalone WordPress EC2 instance"
  value       = aws_eip.web.public_ip
}

output "wordpress_url" {
  description = "🎉 Public web URL to access WordPress in your browser"
  value       = "https://${var.domain_name}"
}

# ------------------------------------------------------------------------------
# Tier: Step 5 - S3 Media Storage & CloudFront CDN Return Values
# ------------------------------------------------------------------------------

output "s3_media_bucket_name" {
  description = "The globally unique name of the S3 media bucket"
  value       = aws_s3_bucket.media.id
}

output "s3_media_bucket_arn" {
  description = "The Amazon Resource Name (ARN) of the S3 media bucket"
  value       = aws_s3_bucket.media.arn
}

output "cloudfront_distribution_id" {
  description = "The unique identifier of the CloudFront CDN distribution"
  value       = aws_cloudfront_distribution.media.id
}

output "cloudfront_distribution_domain_name" {
  description = "The global domain name of the CloudFront CDN distribution"
  value       = aws_cloudfront_distribution.media.domain_name
}

# ------------------------------------------------------------------------------
# Tier: Step 7 - SSL / Domain Return Values [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# ==============================================================================
# 🏢 PROFESSIONAL PRODUCTION SETUP:
# In an enterprise setup with an ALB, outputs expose ACM certificate validation
# CNAME records for Route 53 or external DNS validation.
#
# 💡 STANDALONE / BUDGET MODE:
# ACM is not used in standalone EC2 mode; SSL is managed via Certbot inside the VM.
# ==============================================================================
# output "acm_certificate_arn" {
#   description = "The ARN of the AWS ACM SSL Certificate"
#   value       = aws_acm_certificate.cert.arn
# }
#
# output "acm_certificate_status" {
#   description = "Current validation status of the ACM Certificate"
#   value       = aws_acm_certificate.cert.status
# }
#
# output "acm_dns_validation_records" {
#   description = "DNS CNAME records required by Hostinger to validate the SSL certificate"
#   value = [
#     for dvo in aws_acm_certificate.cert.domain_validation_options : {
#       name   = dvo.resource_record_name
#       type   = dvo.resource_record_type
#       record = dvo.resource_record_value
#     }
#   ]
# }
