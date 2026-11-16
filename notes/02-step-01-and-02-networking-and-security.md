# 🧱 Step 1 & Step 2 Deep Architecture Explanation: Network Foundation & Chained Firewalls

> **Location:** `C:\Users\HP\Desktop\aws-wordpress-infra\STEP-01-AND-02-EXPLANATION.md`  
> **Infrastructure Tiers:** Step 1 (Isolated VPC & Multi-AZ Subnets) + Step 2 (Zero-Trust Chained Firewalls)  
> **AWS Billing / Cost:** **₹0.00 / $0.00 (100% Free Tier & Zero Ongoing Cost)**

---

## 🏛️ Executive Summary: What Have We Built So Far?

In Step 1 and Step 2, we created the **Neev (Foundation)** and **Perimeter Security (Boundary)** for the entire decoupled WordPress cloud architecture in AWS Mumbai (`ap-south-1`):

1. **Step 1 (`vpc.tf` + `variables.tf`):** Created a private, isolated datacenter (VPC) spanning two distinct physical AWS datacenters (Availability Zones `ap-south-1a` and `ap-south-1b`), partitioned cleanly into public and private subnet tiers.
2. **Step 2 (`security-groups.tf`):** Created 4 chained hypervisor-level virtual firewalls ensuring that **only the Application Load Balancer is exposed to the internet**, while Web Servers, MySQL Database, and Redis Cache are completely shielded behind zero-trust boundaries.

---

## 🧱 Detailed Breakdown of Step 1: Isolated Networking Foundation

### Target Code Files:
- `vpc.tf` — Resource definitions for VPC, Subnets, Gateway, Route Tables.
- `variables.tf` — CIDR blocks and IP range parameters.

### 1. Master Custom VPC (`aws_vpc.main`)
- **CIDR Block:** `10.0.0.0/16` (Yields **65,536 private IP addresses**).
- **In Phase 1 Comparison:** In Phase 1, AWS quietly put our EC2 inside the *Default VPC* (`172.31.0.0/16`). Here, we built our own dedicated enterprise VPC.
- **`enable_dns_hostnames = true` (Critical Setting):** In custom VPCs, AWS defaults this to `false`. We explicitly set it to `true` so that AWS assigns internal DNS endpoints (e.g., `wp-db.xxxx.ap-south-1.rds.amazonaws.com`), which are required for WordPress to communicate with RDS.
- **`enable_dns_support = true`:** Activates AWS's internal recursive DNS resolver (`AmazonProvidedDNS` at `10.0.0.2`).

---

### 2. Dual Public Subnets (Application Load Balancer Tier)
- **`public_1` (`10.0.1.0/24`):** Resides in Datacenter A (`ap-south-1a`) — 251 usable host IPs.
- **`public_2` (`10.0.2.0/24`):** Resides in Datacenter B (`ap-south-1b`) — 251 usable host IPs.
- **Why 2 Public Subnets in 2 Availability Zones?**  
  AWS Application Load Balancers (ALBs) enforce a strict architectural prerequisite: they **mandate at least 2 subnets across 2 separate AZs** for High Availability and automated failover.
- **`map_public_ip_on_launch = true`:** Resources launched here receive a public IPv4 address to accept external internet traffic.

---

### 3. Dual Private Subnets (Database & Cache Tier)
- **`private_1` (`10.0.11.0/24`):** Resides in Datacenter A (`ap-south-1a`).
- **`private_2` (`10.0.12.0/24`):** Resides in Datacenter B (`ap-south-1b`).
- **Zero Internet Access:** `map_public_ip_on_launch` is omitted (defaults to `false`). Instances here **can never receive a public IP**, making them completely invisible and unreachable from the public internet.
- **Why 2 Private Subnets?**  
  Amazon RDS *DB Subnet Groups* strictly require at least 2 Availability Zones so the database can support Multi-AZ automated standby failover.

---

### 4. Internet Gateway & Public Routing
- **`aws_internet_gateway.gw`:** The virtual doorway connecting the VPC to the outside internet. Without an IGW, a VPC is an isolated island with zero internet access.
- **`aws_route_table.public`:** Contains the default route:
  ```text
  Destination: 0.0.0.0/0 (All external traffic) ➔ Target: aws_internet_gateway.gw.id
  ```
- **What Actually Makes a Subnet "Public"?**  
  A subnet is NOT public because of its name or IP address. **A subnet becomes public ONLY when its associated route table points `0.0.0.0/0` to an Internet Gateway!**
- **Why Private Subnets are Safe:**  
  Our private subnets are deliberately NOT associated with the public route table. They remain on the VPC's default Main Route Table which has only local routing (`10.0.0.0/16 ➔ local`), making them 100% immune to external internet scans.

---

## 🛡️ Detailed Breakdown of Step 2: Zero-Trust Chained Firewalls

### Target Code File:
- `security-groups.tf` — 4 Chained Firewalls (`alb-sg`, `web-sg`, `db-sg`, `redis-sg`).

### The Architecture of "Security Group Chaining":
In amateur setups, engineers allow traffic using IP ranges (e.g. `10.0.1.0/24`). But IP ranges are fragile — if an instance scales or changes IP, the firewall breaks.  
Instead, we use **Security Group Chaining**: Firewall B says: *"I only trust packets coming from Firewall A's ID (`aws_security_group.alb.id`)"*.

---

### 1. `wp-lab-alb-sg` (Application Load Balancer Firewall)
- **Role:** The **ONLY** entry point exposed to the global internet.
- **Inbound Rules:**
  - Port 80 (HTTP) from `0.0.0.0/0` (Global Internet).
  - Port 443 (HTTPS) from `0.0.0.0/0` (Encrypted web traffic).
- **Outbound Rule:** All traffic (`-1`) to forward requests to the backend EC2 fleet.

---

### 2. `wp-lab-web-sg` (WordPress EC2 Fleet Firewall)
- **Role:** Protects the stateless EC2 compute instances.
- **Inbound Rule:**
  - Port 80 (HTTP) **ONLY from `aws_security_group.alb.id`** (`security_groups = [aws_security_group.alb.id]`).
  - **Zero Public Ingress:** Even though EC2 sits in the network, direct internet requests to EC2 are dropped at the hypervisor level.
- **Port 22 (SSH) 100% ELIMINATED:**
  - In Phase 6, we hardened our architecture by removing Port 22 entirely. Brute-force botnet attacks on SSH are impossible.
  - Server administration is performed securely using **AWS Systems Manager (SSM) Session Manager**.
- **Outbound Rule:** Open to `0.0.0.0/0` so the EC2 instances can communicate with:
  - AWS SSM endpoints (Session Manager shell).
  - Amazon S3 API (WordPress media uploads).
  - Ubuntu APT repositories (OS security updates).

---

### 3. `wp-lab-db-sg` (Amazon RDS MySQL Database Firewall)
- **Role:** Protects the relational database containing WordPress posts, users, and settings.
- **Inbound Rule:**
  - Port 3306 (MySQL) **ONLY from `aws_security_group.web.id`** (`security_groups = [aws_security_group.web.id]`).
  - No other instance or external user can query MySQL.
- **Outbound Rule:** **Zero rules**. A database should never initiate outbound connections.

---

### 4. `wp-lab-redis-sg` (ElastiCache Redis Cache Firewall)
- **Role:** Protects the in-memory Redis cluster powering WordPress Object Cache.
- **Inbound Rule:**
  - Port 6379 (Redis) **ONLY from `aws_security_group.web.id`** (`security_groups = [aws_security_group.web.id]`).
- **Outbound Rule:** **Zero rules**.

---

## 🗺️ Complete End-to-End Traffic Flow Diagram

```text
                                Global Internet (0.0.0.0/0)
                                            │
                                            ▼ HTTPS (443) / HTTP (80)
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ PUBLIC SUBNETS (Step 1)                                                                │
│   Availability Zone A (10.0.1.0/24)        Availability Zone B (10.0.2.0/24)           │
│   └── [ wp-lab-alb-sg ] (Step 2)           └── [ wp-lab-alb-sg ] (Step 2)              │
│       (Public Ingress: 80, 443)                (Public Ingress: 80, 443)               │
└───────────────────────────────────────────┬────────────────────────────────────────────┘
                                            │
                                            ▼ Port 80 ONLY (Chained to alb-sg.id)
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ COMPUTE TIER (Web Servers)                                                             │
│   └── [ wp-lab-web-sg ]                                                                │
│       • Inbound: Port 80 from alb-sg only                                              │
│       • Port 22 (SSH): 100% ELIMINATED (SSM Session Manager only)                      │
│       • Outbound: Open for SSM, S3 API, and APT updates                                │
└─────────────────────────────┬──────────────────────────────────────────┬───────────────┘
                              │                                          │
                              ▼ Port 3306 (MySQL)                        ▼ Port 6379 (Redis)
┌───────────────────────────────────────────────┐ ┌──────────────────────────────────────┐
│ PRIVATE SUBNET A (Step 1 - 10.0.11.0/24)      │ │ PRIVATE SUBNET B (Step 1 - 10.0.12.0)│
│   └── [ wp-lab-db-sg ] (Step 2)               │ │   └── [ wp-lab-redis-sg ] (Step 2)   │
│       (Amazon RDS MySQL 8.0)                  │ │       (Amazon ElastiCache Redis 7.x) │
│       • Inbound: Port 3306 from web-sg only   │ │       • Inbound: Port 6379 (web-sg)  │
│       • Outbound: None (0 rules)              │ │       • Outbound: None (0 rules)     │
└───────────────────────────────────────────────┘ └──────────────────────────────────────┘
```

---

## 💰 Cloud Cost Analysis: How Much Does This Cost?

| Resource | Service | Monthly Cost | Reason |
| :--- | :--- | :--- | :--- |
| **VPC** (`aws_vpc.main`) | Amazon VPC | **₹0.00 / $0.00** | Creating custom VPCs is 100% free in AWS. |
| **Subnets** (Public & Private) | Amazon VPC | **₹0.00 / $0.00** | Subnet IP allocations incur zero cost. |
| **Internet Gateway** (`aws_internet_gateway.gw`) | Amazon VPC | **₹0.00 / $0.00** | AWS does not charge for attaching an IGW. |
| **Route Tables & Associations** | Amazon VPC | **₹0.00 / $0.00** | Virtual route tables are completely free. |
| **Security Groups** (ALB, Web, DB, Redis) | Amazon EC2 | **₹0.00 / $0.00** | Hypervisor firewall rules incur zero cost. |
| **Total Step 1 & Step 2 Cost** | **Infrastructure** | **₹0.00 / $0.00** | **100% Free Tier Compliant!** |

> 💡 **Notice:** AWS bills for *running compute and storage* (EC2 instances, RDS instances, NAT Gateways). Network definitions and firewall rules are pure software-defined metadata that cost nothing!

---

## 🚀 What Is Next?

Now that Step 1 (Networking) and Step 2 (Firewalls) are complete:
- **Step 3 (`iam.tf`):** Provision the EC2 IAM Role, Instance Profile, and attach `AmazonSSMManagedInstanceCore` for zero-SSH management.
- **Step 4 (`rds.tf` + `elasticache.tf`):** Provision the MySQL 8.0 database and Redis caching cluster inside our private subnets.
- **Step 5 (`s3-cloudfront.tf`):** Provision the media bucket with CloudFront Origin Access Control.
- **Step 6 (`compute-alb.tf`):** Provision the Launch Template and Auto Scaling EC2 fleet.
- **Step 7 (`route53.tf`):** Route custom domain and attach SSL certificate.
