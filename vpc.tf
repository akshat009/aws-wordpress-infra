# ==============================================================================
# File: vpc.tf
# Tier: Step 1 - Isolated Networking & Multi-AZ Subnet Foundation
# Description: Provisions a custom Virtual Private Cloud (VPC), 2 Public Subnets
#              for the Load Balancer, 2 Private Subnets for Databases, an Internet
#              Gateway, and explicit Public Route Table Associations.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Master Virtual Private Cloud (VPC)
# ------------------------------------------------------------------------------
# In Phase 1, AWS quietly used the Default VPC (172.31.0.0/16).
# Here, we create an enterprise-grade isolated Custom VPC with 65,536 private IPs.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr # "10.0.0.0/16"
  
  # enable_dns_hostnames: Mandatory! AWS defaults this to false in custom VPCs.
  # If false, EC2 instances and RDS databases will NOT receive internal DNS names
  # (e.g. wp-db.xxxx.ap-south-1.rds.amazonaws.com), breaking database connectivity!
  enable_dns_hostnames = true
  
  # enable_dns_support: Activates AWS internal recursive DNS resolver (AmazonProvidedDNS) at 10.0.0.2
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ------------------------------------------------------------------------------
# 2. Public Subnets (Application Load Balancer Tier)
# ------------------------------------------------------------------------------
# Why 2 Public Subnets in 2 Distinct AZs?
# AWS Application Load Balancers (ALBs) enforce a strict architectural prerequisite:
# They must span at least TWO subnets across TWO Availability Zones for High Availability.

# Public Subnet 1: Located in Mumbai Datacenter A (ap-south-1a)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr # 10.0.1.0/24 (251 usable IPs)
  availability_zone       = "${var.aws_region}a"     # ap-south-1a
  
  # map_public_ip_on_launch = true: Any resource placed here receives a public IPv4 address.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-1"
    Tier = "Public"
  }
}

# Public Subnet 2: Located in Mumbai Datacenter B (ap-south-1b)
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr # 10.0.2.0/24 (251 usable IPs)
  availability_zone       = "${var.aws_region}b"     # ap-south-1b
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-2"
    Tier = "Public"
  }
}

# ------------------------------------------------------------------------------
# 3. Private Subnets (Database & Cache Tier)
# ------------------------------------------------------------------------------
# Security Architecture: Zero Internet Ingress / Zero Public IPs!
# These subnets host our Amazon RDS MySQL 8.0 instance and ElastiCache Redis cluster.
# By omitting 'map_public_ip_on_launch', instances here can NEVER receive a public IP.

# Private Subnet 1: Located in Mumbai Datacenter A (ap-south-1a)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_1_cidr # 10.0.11.0/24 (251 usable IPs)
  availability_zone = "${var.aws_region}a"     # ap-south-1a

  tags = {
    Name = "${var.project_name}-private-1"
    Tier = "Private"
  }
}

# Private Subnet 2: Located in Mumbai Datacenter B (ap-south-1b)
# Required by Amazon RDS DB Subnet Groups (which mandate at least 2 AZs for failover).
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_2_cidr # 10.0.12.0/24 (251 usable IPs)
  availability_zone = "${var.aws_region}b"     # ap-south-1b

  tags = {
    Name = "${var.project_name}-private-2"
    Tier = "Private"
  }
}

# ------------------------------------------------------------------------------
# 4. Internet Gateway (Physical Doorway to the Public Internet)
# ------------------------------------------------------------------------------
# A VPC by itself is completely isolated from the outside world.
# The Internet Gateway (IGW) acts as the virtual router interface between the VPC and the Internet.
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ------------------------------------------------------------------------------
# 5. Public Route Table (The Traffic Director)
# ------------------------------------------------------------------------------
# What makes a subnet "Public"?
# A subnet becomes public ONLY when its associated route table points 0.0.0.0/0 (all traffic)
# to an active Internet Gateway (gateway_id = aws_internet_gateway.gw.id).
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # Default Route: Any destination not within the local VPC (10.0.0.0/16) is routed out to the Internet
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# ------------------------------------------------------------------------------
# 6. Public Route Table Associations
# ------------------------------------------------------------------------------
# Explicitly binds Public Subnet 1 and Public Subnet 2 to the Public Route Table.
# Private subnets are deliberately NOT associated here; they remain on the default Main Route Table
# which has local-only routing (10.0.0.0/16 -> local), making them 100% immune to internet scans.
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}
