# ==============================================================================
# File: security-groups.tf
# Tier: Chained Security Groups & Zero-Trust Perimeter
# Description: Firewalls use Security Group Chaining (a rule's source is another
#              security group, not an IP range). All 4 groups exist in every
#              mode: they cost nothing, and keeping them avoids
#              DependencyViolation errors when switching modes.
#
# WARNING: never edit a security group's `name` or `description` - AWS cannot
# change them in place, so Terraform would delete and recreate the group.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Application Load Balancer (ALB) Security Group
# ------------------------------------------------------------------------------
# The only thing in enterprise mode that accepts traffic from the internet.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Public ingress firewall for Application Load Balancer (HTTP/HTTPS)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow plain HTTP traffic from global internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow encrypted HTTPS traffic from global internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
    Tier = "Ingress"
  }
}

# ------------------------------------------------------------------------------
# 2. Web Tier (EC2) Security Group
# ------------------------------------------------------------------------------
# Inbound rules follow architecture_mode automatically:
#   standalone / migrating : 80 + 443 from the internet (no ALB in front)
#   enterprise             : 80 ONLY from the ALB security group
# Port 22 (SSH) is closed in every mode; access is through SSM Session Manager.
locals {
  web_public_ingress = local.run_standalone ? {
    80  = "Allow HTTP directly from global internet (Non-ALB standalone mode)"
    443 = "Allow HTTPS directly from global internet (Non-ALB standalone mode)"
  } : {}
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Firewall for WordPress EC2 instances - chained strictly to ALB SG"
  vpc_id      = aws_vpc.main.id

  # Standalone: direct public ingress on 80/443
  dynamic "ingress" {
    for_each = local.web_public_ingress
    content {
      description = ingress.value
      from_port   = ingress.key
      to_port     = ingress.key
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Enterprise: port 80 only from the ALB (security group chaining)
  dynamic "ingress" {
    for_each = local.run_fleet ? [80] : []
    content {
      description     = "Allow HTTP strictly from Application Load Balancer"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.alb.id]
    }
  }

  # Outbound: SSM endpoints, S3, RDS, Ubuntu package mirrors, Let's Encrypt
  egress {
    description = "Allow all outbound traffic for SSM agent, S3 uploads, and OS updates"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
    Tier = "Compute"
  }
}

# ------------------------------------------------------------------------------
# 3. Database Tier (Amazon RDS MySQL) Security Group
# ------------------------------------------------------------------------------
# MySQL 3306 only from web servers. Used by RDS in migrating/enterprise modes.
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Firewall for Amazon RDS MySQL - chained strictly to EC2 Web SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL queries strictly from WordPress web instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
    Tier = "Database"
  }
}

# ------------------------------------------------------------------------------
# 4. Cache Tier (Amazon ElastiCache Redis) Security Group
# ------------------------------------------------------------------------------
# Reserved for a future ElastiCache Redis object cache (not provisioned yet).
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Firewall for ElastiCache Redis - chained strictly to EC2 Web SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow Redis cache commands strictly from WordPress web instances"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  tags = {
    Name = "${var.project_name}-redis-sg"
    Tier = "Cache"
  }
}
