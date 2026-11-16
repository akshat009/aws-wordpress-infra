# ==============================================================================
# File: rds.tf
# Tier: Step 4 - Decoupled Managed Relational Database (Amazon RDS MySQL)
# Description: Provisions an isolated Amazon RDS MySQL 8.0 instance residing
#              in private subnets across multiple Availability Zones with
#              zero public ingress, automatic daily backups, and storage autoscaling.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. DB Subnet Group (Multi-AZ Private Placement)
# ------------------------------------------------------------------------------
# In Phase 4, we decoupled the database from the local EC2 disk.
# AWS RDS requires a DB Subnet Group spanning at least TWO distinct Availability Zones,
# even when launching a single-AZ instance. This guarantees that if Multi-AZ failover
# is enabled in the future, standby subnets are already registered.
# Both subnets (private_1 and private_2) have zero internet routing!
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Private database subnet group spanning Availability Zones ap-south-1a and ap-south-1b"
  subnet_ids  = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ------------------------------------------------------------------------------
# 2. Amazon RDS MySQL 8.0 Instance
# ------------------------------------------------------------------------------
# Decoupling Benefits:
# 1. Stateless Compute: If an EC2 web server crashes or ASG terminates it, ZERO data is lost!
# 2. Managed Automated Backups: AWS handles point-in-time recovery and snapshot lifecycles.
# 3. High Performance: Dedicated memory and IOPS separate from Nginx and PHP execution.
resource "aws_db_instance" "wordpress" {
  identifier = "${var.project_name}-db"

  # Engine & Version
  engine         = "mysql"
  engine_version = "8.0" # AWS automatically assigns latest minor version (e.g. 8.0.36)

  # Hardware Capacity & Storage
  instance_class        = var.db_instance_class    # "db.t3.micro" (AWS Free Tier eligible)
  allocated_storage     = var.db_allocated_storage # 20 GB (Free Tier limit)
  max_allocated_storage = 50                       # Automatically scale storage up to 50 GB if disk fills
  storage_type          = "gp3"                    # General Purpose SSD with baseline 3,000 IOPS

  # Database Credentials & Initial Schema
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network & Security Tier Placement
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id] # Chained strictly to web-sg (Port 3306)
  publicly_accessible    = false                      # CRITICAL: Zero internet access. Unreachable from outside VPC.

  # High Availability & Backups
  multi_az                = false         # Single-AZ for lab cost optimization
  backup_retention_period = 1             # Retain automated daily snapshots for 1 day
  backup_window           = "03:00-04:00" # Daily snapshot window (UTC)
  maintenance_window      = "Sun:04:30-Sun:05:30"

  # Lab Teardown Convenience
  skip_final_snapshot = true  # Allows clean terraform destroy without blocking on final snapshot creation
  deletion_protection = false # Prevents accidental terraform destroy block

  tags = {
    Name = "${var.project_name}-rds"
  }
}
