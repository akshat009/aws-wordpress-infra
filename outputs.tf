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
