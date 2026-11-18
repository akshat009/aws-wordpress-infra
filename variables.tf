# ==============================================================================
# File: variables.tf
# Tier: Input Variables
# Description: Every tunable setting for the stack. The most important one is
#              architecture_mode at the top: change it to move between the
#              $0 standalone setup and the enterprise (RDS + ALB) setup.
# ==============================================================================

# ==============================================================================
# ARCHITECTURE SWITCH (change this one value, then push)
# ==============================================================================
# "standalone" : 1 EC2 + local MySQL + Elastic IP + Let's Encrypt     (~$0 on Free Tier)
# "migrating"  : standalone keeps serving, PLUS RDS + ACM certificate are created.
#                Use this stage to copy the database and validate the certificate.
# "enterprise" : ALB + Auto Scaling Group + RDS + ACM (TLS 1.3); standalone removed.
#
# Upgrade:   standalone -> migrating -> enterprise
# Downgrade: enterprise -> migrating -> standalone
# Step-by-step runbook: README.md -> "Switching architecture modes".
variable "architecture_mode" {
  description = "Which architecture to build: standalone, migrating or enterprise"
  type        = string
  default     = "standalone"

  validation {
    condition     = contains(["standalone", "migrating", "enterprise"], var.architecture_mode)
    error_message = "architecture_mode must be one of: standalone, migrating, enterprise."
  }
}

# ------------------------------------------------------------------------------
# Individual feature switches (override the architecture_mode preset)
# ------------------------------------------------------------------------------
# null (default) = follow the preset above. true/false = force that feature on/off.
# Examples:
#   architecture_mode = "standalone", enable_rds = true  -> 1 server + RDS, no load balancer
#   architecture_mode = "standalone", enable_alb = true  -> load balancer in front of 1 server
#   enable_asg = true needs enable_alb and enable_rds (checked at plan time, see locals.tf)
variable "enable_rds" {
  description = "Force RDS on/off. null = follow architecture_mode."
  type        = bool
  default     = null
}

variable "enable_alb" {
  description = "Force the Application Load Balancer + ACM HTTPS on/off (works with a single server too). null = follow architecture_mode."
  type        = bool
  default     = null
}

variable "enable_asg" {
  description = "Force the Auto Scaling fleet on/off (replaces the single server; needs enable_alb and enable_rds). null = follow architecture_mode."
  type        = bool
  default     = null
}

# ------------------------------------------------------------------------------
# General Project & Environment Variables
# ------------------------------------------------------------------------------

# No defaults: these three are set per project, on Day 0.
#   CI     : TF_VAR_* from the AWS_REGION / PROJECT_NAME / DOMAIN_NAME repository variables
#   Laptop : terraform.tfvars (copy of terraform.tfvars.example)
variable "aws_region" {
  description = "AWS region where all resources are provisioned (e.g. ap-south-1)"
  type        = string
}

variable "project_name" {
  description = "Naming prefix applied to all resources, tags and security groups (e.g. wp-lab)"
  type        = string
}

variable "environment" {
  description = "Deployment lifecycle stage (e.g. dev, staging, prod, lab)"
  type        = string
  default     = "lab"
}

variable "domain_name" {
  description = "Custom domain or subdomain for WordPress (CI sets this from the DOMAIN_NAME repo variable)"
  type        = string
}

# ------------------------------------------------------------------------------
# Networking (VPC & Subnets)
# ------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC (/16 = 65,536 private IPs)"
  type        = string
  default     = "10.0.0.0/16"
}

# Public subnets: ALB and web servers. ALBs require 2 subnets in 2 AZs.
variable "public_subnet_1_cidr" {
  description = "CIDR block for Public Subnet 1 (AZ a of aws_region)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for Public Subnet 2 (AZ b of aws_region)"
  type        = string
  default     = "10.0.2.0/24"
}

# Private subnets: RDS and Redis. No internet route at all.
variable "private_subnet_1_cidr" {
  description = "CIDR block for Private Subnet 1 (AZ a of aws_region)"
  type        = string
  default     = "10.0.11.0/24"
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for Private Subnet 2 (AZ b of aws_region)"
  type        = string
  default     = "10.0.12.0/24"
}

# ------------------------------------------------------------------------------
# Database
# ------------------------------------------------------------------------------
# The password is NOT a variable any more: Terraform generates it and stores it
# in SSM Parameter Store as a SecureString (see secrets.tf).

variable "db_name" {
  description = "WordPress database name"
  type        = string
  default     = "wordpress"
}

variable "db_username" {
  description = "WordPress database user (also the RDS master user)"
  type        = string
  default     = "wpuser"
}

variable "db_instance_class" {
  description = "RDS instance size (db.t3.micro is Free Tier eligible)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Initial RDS storage in GB (Free Tier includes 20 GB)"
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Run a standby RDS replica in a second AZ (production HA; roughly doubles RDS cost)"
  type        = bool
  default     = false
}

variable "rds_backup_retention_days" {
  description = "Days of automated RDS backups (point-in-time recovery window)"
  type        = number
  default     = 7
}

variable "rds_deletion_protection" {
  description = "Block RDS deletion. Set true in production; must be false before downgrading to standalone."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# Compute & Auto Scaling
# ------------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 size for WordPress servers (t3.micro is Free Tier eligible)"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum number of servers in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_desired_capacity" {
  description = "Starting number of servers in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of servers during traffic spikes"
  type        = number
  default     = 4
}

variable "asg_cpu_target" {
  description = "Average CPU % the Auto Scaling Group tries to hold (target tracking)"
  type        = number
  default     = 60
}

# ------------------------------------------------------------------------------
# Monitoring, Cost & Backups
# ------------------------------------------------------------------------------

variable "alert_email" {
  description = "Email for alarms and budget alerts (CI sets this from the ALERT_EMAIL repo variable). Empty = no email subscription."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly AWS spend limit; alerts at 80% actual and 100% forecast"
  type        = number
  default     = 10
}

variable "enable_backups" {
  description = "Daily AWS Backup snapshots of the standalone server and RDS, kept 7 days (small cost, usually under $1/month)"
  type        = bool
  default     = false
}

variable "enable_alarms" {
  description = "CloudWatch alarms (auto-recovery, CPU, ALB, RDS). The SNS alert topic always exists."
  type        = bool
  default     = true
}

variable "enable_budget" {
  description = "Monthly AWS budget with 80% actual / 100% forecast alerts"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Backup / maintenance times (UTC). Defaults = night time in India (IST = UTC+5:30);
# move them to your own quiet hours.
# ------------------------------------------------------------------------------
variable "rds_backup_window" {
  description = "Daily RDS automatic backup window, UTC (hh24:mi-hh24:mi). Default 02:00-03:00 IST"
  type        = string
  default     = "20:30-21:30"
}

variable "rds_maintenance_window" {
  description = "Weekly RDS maintenance window, UTC (ddd:hh24:mi-ddd:hh24:mi); must not overlap the backup window"
  type        = string
  default     = "Sun:21:45-Sun:22:45"
}

variable "backup_schedule" {
  description = "AWS Backup daily schedule, cron in UTC (used when enable_backups = true). Default 02:30 IST"
  type        = string
  default     = "cron(0 21 * * ? *)"
}
