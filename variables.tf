# ==============================================================================
# File: variables.tf
# Tier: Step 1 - Parameterized Input Variables
# Description: Defines reusable, typed variables for cloud regions, naming,
#              environments, and CIDR subnet address blocks.
# ==============================================================================

# ------------------------------------------------------------------------------
# General Project & Environment Variables
# ------------------------------------------------------------------------------

variable "aws_region" {
  description = "The target AWS geographic region where all resources are provisioned"
  type        = string
  default     = "ap-south-1" # Asia Pacific (Mumbai)
}

variable "project_name" {
  description = "Standard naming prefix applied to all resources, tags, and security groups"
  type        = string
  default     = "wp-lab"
}

variable "environment" {
  description = "Deployment lifecycle stage (e.g. dev, staging, prod, lab)"
  type        = string
  default     = "lab"
}

# ------------------------------------------------------------------------------
# Networking Tier Variables (Step 1 - VPC & Subnets)
# ------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "Master Classless Inter-Domain Routing (CIDR) block for the isolated VPC. /16 yields 65,536 total private IP addresses."
  type        = string
  default     = "10.0.0.0/16"
}

# Public Subnets (For Application Load Balancer & Public Ingress)
# AWS ALBs require a minimum of 2 public subnets in 2 distinct Availability Zones.
variable "public_subnet_1_cidr" {
  description = "CIDR block for Public Subnet 1 residing in Availability Zone ap-south-1a (/24 yields 251 usable host IPs)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for Public Subnet 2 residing in Availability Zone ap-south-1b (/24 yields 251 usable host IPs)."
  type        = string
  default     = "10.0.2.0/24"
}

# Private Subnets (For Amazon RDS MySQL Database & ElastiCache Redis Cluster)
# Zero internet routing. Dedicated exclusively to backend stateful data stores.
variable "private_subnet_1_cidr" {
  description = "CIDR block for Private Subnet 1 (RDS Primary & Redis Node A) in Availability Zone ap-south-1a."
  type        = string
  default     = "10.0.11.0/24"
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for Private Subnet 2 (RDS Standby & Redis Node B) in Availability Zone ap-south-1b."
  type        = string
  default     = "10.0.12.0/24"
}
