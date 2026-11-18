# ==============================================================================
# File: rds.tf
# Tier: Managed Database (Amazon RDS MySQL)
# Description: RDS MySQL in private subnets across 2 AZs, no public access,
#              encrypted, with automated backups. Exists when
#              architecture_mode is "migrating" or "enterprise" (local.run_rds).
#
# In "standalone" mode WordPress uses MySQL on the EC2 itself (localhost).
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. DB Subnet Group (private subnets in 2 AZs)
# ------------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  count = local.run_rds ? 1 : 0

  name        = "${var.project_name}-db-subnet-group"
  description = "Private database subnet group spanning Availability Zones ap-south-1a and ap-south-1b"
  subnet_ids  = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# Unique suffix for the final snapshot taken when RDS is deleted (downgrade).
# Regenerated each time RDS is created, so snapshot names never collide.
resource "random_id" "db_final_snapshot" {
  count = local.run_rds ? 1 : 0

  byte_length = 4
}

# ------------------------------------------------------------------------------
# 2. Amazon RDS MySQL Instance
# ------------------------------------------------------------------------------
resource "aws_db_instance" "wordpress" {
  count = local.run_rds ? 1 : 0

  identifier = "${var.project_name}-db"

  # MySQL 8.4 LTS. RDS MySQL 8.0 left standard support on 31 July 2026; new 8.0
  # instances would be billed for RDS Extended Support (far more than the
  # instance itself on a db.t3.micro).
  engine         = "mysql"
  engine_version = "8.4"

  # Never auto-enrol in paid Extended Support; plan the major upgrade instead.
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"

  # Capacity & storage
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 50    # Storage autoscaling ceiling
  storage_type          = "gp3" # Baseline 3,000 IOPS
  storage_encrypted     = true  # Encryption at rest (AWS managed KMS key)

  # Credentials: password generated in secrets.tf, never in code
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  # Network placement: private subnets, reachable only from web-sg on 3306
  db_subnet_group_name   = aws_db_subnet_group.main[0].name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # Availability & backups
  multi_az                   = var.rds_multi_az
  backup_retention_period    = var.rds_backup_retention_days
  backup_window              = "20:30-21:30"         # UTC = 02:00-03:00 IST
  maintenance_window         = "Sun:21:45-Sun:22:45" # UTC, after the backup window
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  # Deletion safety: a final snapshot is always taken when RDS is deleted
  deletion_protection       = var.rds_deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-db-final-${random_id.db_final_snapshot[0].hex}"

  tags = {
    Name   = "${var.project_name}-rds"
    Backup = "daily" # Picked up by backup.tf when enable_backups = true
  }
}
