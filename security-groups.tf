# ==============================================================================
# File: security-groups.tf
# Tier: Step 2 - Chained Security Groups & Zero-Trust Perimeter
# Description: Defines the 4 tightly coupled hypervisor firewalls using Security
#              Group Chaining (source SG referencing) instead of fragile IP CIDRs.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Application Load Balancer (ALB) Security Group
# ------------------------------------------------------------------------------
# Role: The ONLY component in our entire AWS infrastructure that exposes open ports
#       to the global internet. Listens for public web requests on HTTP and HTTPS.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Public ingress firewall for Application Load Balancer (HTTP/HTTPS)"
  vpc_id      = aws_vpc.main.id # Binds this firewall to our custom WordPress VPC

  # Inbound Rule 1: HTTP (Port 80) from anywhere in the world
  ingress {
    description = "Allow plain HTTP traffic from global internet (redirected to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound Rule 2: HTTPS (Port 443) from anywhere in the world
  ingress {
    description = "Allow encrypted HTTPS traffic from global internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Rule: Allows ALB to forward traffic to backend EC2 instances on port 80
  egress {
    description = "Allow all outbound traffic to forward requests to target EC2 instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
    Tier = "Ingress"
  }
}

# ------------------------------------------------------------------------------
# 2. Web Tier (EC2 Auto Scaling Fleet) Security Group
# ------------------------------------------------------------------------------
# Role: Protects the WordPress EC2 instances.
# Zero-Trust Standard:
# 1. Web servers NEVER accept direct traffic from 0.0.0.0/0!
# 2. Port 80 is strictly locked to traffic forwarded by the ALB Security Group.
# 3. Port 22 (SSH) is 100% ELIMINATED! Management is done via AWS SSM Session Manager.
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Firewall for WordPress EC2 instances - chained strictly to ALB SG"
  vpc_id      = aws_vpc.main.id

  # Inbound Rule: HTTP (Port 80) ONLY from the Application Load Balancer
  # Notice: 'security_groups' is used instead of 'cidr_blocks' (Security Group Chaining!)
  # 💡 NOTE (IF NO LOAD BALANCER): If running a standalone EC2 without an ALB, change
  #    'security_groups = [aws_security_group.alb.id]' to 'cidr_blocks = ["0.0.0.0/0"]'
  #    and add another ingress block for port 443 with 'cidr_blocks = ["0.0.0.0/0"]'.
  ingress {
    description     = "Allow HTTP strictly from Application Load Balancer (no direct internet ingress)"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Outbound Rule: Required for EC2 to reach external AWS APIs and package repositories:
  # - AWS SSM Session Manager endpoints (outbound 443)
  # - Amazon S3 media upload API (outbound 443)
  # - Ubuntu APT repository updates (outbound 80/443)
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
# 3. Database Tier (Amazon RDS MySQL 8.0) Security Group
# ------------------------------------------------------------------------------
# Role: Protects the relational MySQL database hosting WordPress tables.
# Security Architecture:
# - Placed in private subnets with ZERO public IP capability.
# - Port 3306 accepts connections ONLY from instances bearing the 'web-sg' identity.
# - Even if an attacker enters the VPC, they cannot query MySQL without the web-sg tag.
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Firewall for Amazon RDS MySQL - chained strictly to EC2 Web SG"
  vpc_id      = aws_vpc.main.id

  # Inbound Rule: MySQL (Port 3306) strictly from the WordPress EC2 Fleet
  ingress {
    description     = "Allow MySQL queries strictly from WordPress web instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id] # Chained strictly to web-sg!
  }

  # Outbound Rule: None. A database should NEVER initiate outbound connections to the internet.

  tags = {
    Name = "${var.project_name}-db-sg"
    Tier = "Database"
  }
}

# ------------------------------------------------------------------------------
# 4. Cache Tier (Amazon ElastiCache Redis 7.x) Security Group
# ------------------------------------------------------------------------------
# Role: Protects the in-memory Redis cluster powering WordPress Object Cache.
# Security Architecture:
# - Placed in private subnets with ZERO public IP capability.
# - Port 6379 accepts TCP packets ONLY from instances bearing the 'web-sg' identity.
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Firewall for ElastiCache Redis - chained strictly to EC2 Web SG"
  vpc_id      = aws_vpc.main.id

  # Inbound Rule: Redis (Port 6379) strictly from the WordPress EC2 Fleet
  ingress {
    description     = "Allow Redis cache commands strictly from WordPress web instances"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id] # Chained strictly to web-sg!
  }

  # Outbound Rule: None. An in-memory cache cluster never initiates outbound connections.

  tags = {
    Name = "${var.project_name}-redis-sg"
    Tier = "Cache"
  }
}

