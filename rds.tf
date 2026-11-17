# ==============================================================================
# File: rds.tf
# Tier: Step 4 - Decoupled Managed Relational Database (Amazon RDS MySQL)
# Description: Provisions an isolated Amazon RDS MySQL 8.0 instance residing
#              in private subnets across multiple Availability Zones with
#              zero public ingress, automatic daily backups, and storage autoscaling.
# ==============================================================================

# ==============================================================================
# 🏢 PROFESSIONAL PRODUCTION SETUP:
# In an enterprise/production setup, the database MUST be decoupled into a managed
# Amazon RDS instance residing in isolated private subnets across multiple AZs.
# This guarantees:
# 1. Stateless Compute: Web servers can crash, restart, or scale without risking data loss.
# 2. Automated Backups & Point-in-time Recovery managed by AWS.
# 3. High Availability: Multi-AZ standby replica ready for automatic failover.
# 4. Storage Autoscaling: DB disk expands automatically as WordPress grows.
# 5. Fault Isolation: Memory leaks or CPU spikes in PHP cannot kill the database process.
#
# 💡 STANDALONE / BUDGET MODE:
# For a single-server standalone setup, this RDS resource is COMMENTED OUT to save
# cost. WordPress will connect to a local MySQL server (localhost) running directly
# inside the EC2 instance.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. DB Subnet Group (Multi-AZ Private Placement) [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_db_subnet_group" "main" {
#   name        = "${var.project_name}-db-subnet-group"
#   description = "Private database subnet group spanning Availability Zones ap-south-1a and ap-south-1b"
#   subnet_ids  = [aws_subnet.private_1.id, aws_subnet.private_2.id]
#
#   tags = {
#     Name = "${var.project_name}-db-subnet-group"
#   }
# }

# ------------------------------------------------------------------------------
# 2. Amazon RDS MySQL 8.0 Instance [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_db_instance" "wordpress" {
#   identifier = "${var.project_name}-db"
#
#   # Engine & Version
#   engine         = "mysql"
#   engine_version = "8.0" # AWS automatically assigns latest minor version (e.g. 8.0.36)
#
#   # Hardware Capacity & Storage
#   instance_class        = var.db_instance_class    # "db.t3.micro" (AWS Free Tier eligible)
#   allocated_storage     = var.db_allocated_storage # 20 GB (Free Tier limit)
#   max_allocated_storage = 50                       # Automatically scale storage up to 50 GB if disk fills
#   storage_type          = "gp3"                    # General Purpose SSD with baseline 3,000 IOPS
#
#   # Database Credentials & Initial Schema
#   db_name  = var.db_name
#   username = var.db_username
#   password = var.db_password
#
#   # Network & Security Tier Placement
#   db_subnet_group_name   = aws_db_subnet_group.main.name
#   vpc_security_group_ids = [aws_security_group.db.id] # Chained strictly to web-sg (Port 3306)
#   publicly_accessible    = false                      # CRITICAL: Zero internet access. Unreachable from outside VPC.
#
#   # High Availability & Backups
#   multi_az                = false         # Single-AZ for lab cost optimization
#   backup_retention_period = 1             # Retain automated daily snapshots for 1 day
#   backup_window           = "03:00-04:00" # Daily snapshot window (UTC)
#   maintenance_window      = "Sun:04:30-Sun:05:30"
#
#   # Lab Teardown Convenience
#   skip_final_snapshot = true  # Allows clean terraform destroy without blocking on final snapshot creation
#   deletion_protection = false # Prevents accidental terraform destroy block
#
#   tags = {
#     Name = "${var.project_name}-rds"
#   }
# }
