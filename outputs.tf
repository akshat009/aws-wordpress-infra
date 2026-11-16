# ==============================================================================
# File: outputs.tf
# Tier: Step 1 - Networking Return Values (Outputs)
# Description: Exposes critical resource IDs and network attributes generated
#              during Step 1 for downstream modules and operator inspection.
# ==============================================================================

# The Master VPC ID (Referenced later by Security Groups and Peering)
output "vpc_id" {
  description = "The unique AWS resource identifier of the provisioned custom VPC (e.g. vpc-0a1b2c3d4e5f)"
  value       = aws_vpc.main.id
}

# Master VPC CIDR Block
output "vpc_cidr_block" {
  description = "The primary IPv4 address block allocated to the custom VPC (10.0.0.0/16)"
  value       = aws_vpc.main.cidr_block
}

# Public Subnets (Referenced by the Application Load Balancer in Step 5)
output "public_subnet_ids" {
  description = "List of Public Subnet IDs spanning Availability Zones ap-south-1a and ap-south-1b"
  value       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# Private Subnets (Referenced by Amazon RDS DB Subnet Group and Redis Cache Subnet Group)
output "private_subnet_ids" {
  description = "List of Private Subnet IDs spanning Availability Zones ap-south-1a and ap-south-1b"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

# Internet Gateway ID
output "internet_gateway_id" {
  description = "The unique AWS resource identifier of the attached Internet Gateway"
  value       = aws_internet_gateway.gw.id
}

# ------------------------------------------------------------------------------
# Tier: Step 2 - Security Group Return Values (Outputs)
# ------------------------------------------------------------------------------

output "alb_security_group_id" {
  description = "Security group ID attached to the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "web_security_group_id" {
  description = "Security group ID attached to the WordPress EC2 instances"
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
# Tier: Step 3 - IAM Return Values (Outputs)
# ------------------------------------------------------------------------------

output "ec2_iam_role_name" {
  description = "Name of the IAM Role attached to WordPress EC2 instances"
  value       = aws_iam_role.ec2.name
}

output "ec2_iam_role_arn" {
  description = "ARN of the IAM Role attached to WordPress EC2 instances"
  value       = aws_iam_role.ec2.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the IAM Instance Profile attached to WordPress Launch Template"
  value       = aws_iam_instance_profile.ec2.name
}

output "ec2_instance_profile_arn" {
  description = "ARN of the IAM Instance Profile attached to WordPress Launch Template"
  value       = aws_iam_instance_profile.ec2.arn
}

# ------------------------------------------------------------------------------
# Tier: Step 4 - Relational Database Return Values (Outputs)
# ------------------------------------------------------------------------------

output "rds_endpoint" {
  description = "The connection endpoint for the Amazon RDS MySQL database (Host:Port)"
  value       = aws_db_instance.wordpress.endpoint
}

output "rds_address" {
  description = "The DNS hostname address of the RDS MySQL database (used in wp-config.php)"
  value       = aws_db_instance.wordpress.address
}

output "rds_port" {
  description = "The database listening port (default MySQL: 3306)"
  value       = aws_db_instance.wordpress.port
}

output "rds_database_name" {
  description = "The initial MySQL database name"
  value       = aws_db_instance.wordpress.db_name
}

output "rds_username" {
  description = "Master administrative username for database connections"
  value       = aws_db_instance.wordpress.username
}

# ------------------------------------------------------------------------------
# Tier: Step 6 - Compute & Application Load Balancer Return Values (Outputs)
# ------------------------------------------------------------------------------

output "alb_dns_name" {
  description = "The public dynamic DNS endpoint of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "The Amazon Resource Name (ARN) of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "target_group_arn" {
  description = "The Amazon Resource Name (ARN) of the ALB Target Group"
  value       = aws_lb_target_group.web.arn
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group managing WordPress web servers"
  value       = aws_autoscaling_group.web.name
}

output "wordpress_url" {
  description = "🎉 The live secure public web URL to access WordPress in your browser"
  value       = "https://${var.domain_name}"
}

# ------------------------------------------------------------------------------
# Tier: Step 5 - S3 Media Storage & CloudFront CDN Return Values (Outputs)
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
# Tier: Step 7 - SSL / Domain Return Values (Outputs)
# ------------------------------------------------------------------------------

output "acm_certificate_arn" {
  description = "The ARN of the AWS ACM SSL Certificate"
  value       = aws_acm_certificate.cert.arn
}

output "acm_certificate_status" {
  description = "Current validation status of the ACM Certificate"
  value       = aws_acm_certificate.cert.status
}

output "acm_dns_validation_records" {
  description = "DNS CNAME records required by Hostinger to validate the SSL certificate"
  value = [
    for dvo in aws_acm_certificate.cert.domain_validation_options : {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  ]
}
