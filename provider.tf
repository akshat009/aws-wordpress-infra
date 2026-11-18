# ==============================================================================
# File: provider.tf
# Tier: Foundation & Backend Configuration
# Description: Terraform version requirements, providers, remote S3 state
#              storage and DynamoDB state locking.
# ==============================================================================

terraform {
  # Minimum Terraform CLI version (moved blocks, preconditions, one()).
  required_version = ">= 1.5.0"

  required_providers {
    # Official AWS provider; "~> 5.0" allows 5.x updates but blocks breaking 6.x.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Generates the database password so it never lives in code (see secrets.tf).
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # ----------------------------------------------------------------------------
  # Remote State Storage & Distributed Lock (created once, by hand, on Day 0)
  # ----------------------------------------------------------------------------
  # 1. Team collaboration: every runner reads one source of truth.
  # 2. Secret protection: state holds sensitive values; encrypted at rest.
  # 3. DynamoDB lock: stops two applies from corrupting state at the same time.
  backend "s3" {
    bucket         = "wp-lab-tfstate-538820337783"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "wp-lab-tf-locks"
    encrypt        = true
  }
}

# ------------------------------------------------------------------------------
# AWS Provider Configuration
# ------------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  # Applied to every resource: cost allocation and "who owns this" in one place.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
