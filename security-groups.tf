# ==============================================================================
# File: security-groups.tf
# Tier: Step 2 - Chained Security Groups & Zero-Trust Perimeter
# Description: Defines the hypervisor firewalls using Security Group Chaining
#              (source SG referencing) instead of fragile IP CIDRs.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Application Load Balancer (ALB) Security Group
# ------------------------------------------------------------------------------
# ==============================================================================
# 🏢 PROFESSIONAL PRODUCTION SETUP:
# In an enterprise/production setup, the ALB Security Group is the ONLY component
# in the entire cloud infrastructure exposed to 0.0.0.0/0 on Port 80 and 443.
# All backend web servers sit shielded behind the ALB and never accept direct traffic.
# (Kept in code to prevent DependencyViolation during standalone migration; cost = $0).
# ==============================================================================
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
# 2. Web Tier (EC2 Compute) Security Group
# ------------------------------------------------------------------------------
# Role: Protects the WordPress EC2 instances.
#
# ==============================================================================
# 🏢 PROFESSIONAL PRODUCTION SETUP:
# In an enterprise setup, Web servers NEVER accept direct traffic from 0.0.0.0/0!
# Inbound Port 80 is strictly locked to traffic forwarded by the ALB Security Group:
#   ingress {
#     description     = "Allow HTTP strictly from ALB (no direct internet ingress)"
#     from_port       = 80
#     to_port         = 80
#     protocol        = "tcp"
#     security_groups = [aws_security_group.alb.id] # Security Group Chaining!
#   }
# Port 22 (SSH) is 100% ELIMINATED! Management is done via AWS SSM Session Manager.
#
# 💡 STANDALONE / BUDGET MODE:
# Since ALB is removed, the standalone web server must listen directly to public
# internet traffic (0.0.0.0/0) on Port 80 and Port 443. Port 22 SSH still remains closed.
# ==============================================================================
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Firewall for WordPress EC2 instances - chained strictly to ALB SG"
  vpc_id      = aws_vpc.main.id

  # ----------------------------------------------------------------------------
  # 🏢 PROFESSIONAL PRODUCTION INGRESS (COMMENTED OUT IN STANDALONE MODE):
  # ----------------------------------------------------------------------------
  # ingress {
  #   description     = "Allow HTTP strictly from Application Load Balancer"
  #   from_port       = 80
  #   to_port         = 80
  #   protocol        = "tcp"
  #   security_groups = [aws_security_group.alb.id]
  # }

  # ----------------------------------------------------------------------------
  # 💡 STANDALONE MODE INGRESS (Direct Public Ingress for Port 80 & 443):
  # ----------------------------------------------------------------------------
  ingress {
    description = "Allow HTTP directly from global internet (Non-ALB standalone mode)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS directly from global internet (Non-ALB standalone mode)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
# ==============================================================================
# 🏢 PROFESSIONAL PRODUCTION SETUP:
# In an enterprise setup, Amazon RDS MySQL has its own dedicated firewall placed
# in private subnets, chained strictly to accept Port 3306 ONLY from web-sg.
# (Kept in code to prevent DependencyViolation during standalone migration; cost = $0).
# ==============================================================================
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
# 4. Cache Tier (Amazon ElastiCache Redis 7.x) Security Group
# ------------------------------------------------------------------------------
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
