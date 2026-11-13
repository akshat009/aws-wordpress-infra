# ==============================================================================
# File: provider.tf
# Tier: Step 1 - Foundation & Backend Configuration
# Description: Configures the Terraform binary requirements, AWS provider,
#              remote S3 state storage, and DynamoDB distributed locking.
# ==============================================================================

terraform {
  # Minimum required Terraform CLI version to ensure HCL2 feature compatibility
  required_version = ">= 1.5.0"

  # Official HashiCorp AWS Provider declaration with semantic version constraint (~> 5.0)
  # This allows non-breaking minor/patch updates within v5.x while preventing accidental v6.x breaking upgrades.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ----------------------------------------------------------------------------
  # Remote State Storage & Distributed Concurrency Lock
  # ----------------------------------------------------------------------------
  # Why Remote S3 State over Local Disk?
  # 1. Team Collaboration: Multiple developers/runners read the single source of truth.
  # 2. Secret Protection: State file contains plain-text attributes; encrypted at rest via AES256.
  # 3. DynamoDB State Lock: Prevents two simultaneous 'apply' operations from corrupting state.
  backend "s3" {
    bucket         = "wp-lab-tfstate-538820337783" # Dedicated private S3 bucket created in Phase 10
    key            = "prod/terraform.tfstate"      # Remote object path inside the S3 bucket
    region         = "ap-south-1"                  # AWS Mumbai region
    dynamodb_table = "wp-lab-tf-locks"             # DynamoDB table holding active execution locks (LockID)
    encrypt        = true                          # Enforces Server-Side Encryption (SSE-S3 / AES256)
  }
}

# ------------------------------------------------------------------------------
# AWS Provider Configuration
# ------------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region # Defaults to ap-south-1 (Mumbai)

  # Default Tags automatically propagate to EVERY single resource managed by this provider.
  # Crucial for Phase 11 cost allocation billing tags and AWS Cost Explorer grouping.
  default_tags {
    tags = {
      Project     = var.project_name # "wp-lab"
      Environment = var.environment  # "lab"
      ManagedBy   = "Terraform"      # Flags resource as automated IaC (never manually edit in console)
    }
  }
}
