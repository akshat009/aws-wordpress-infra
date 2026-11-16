# ☁️ AWS Decoupled WordPress Infrastructure (Terraform)

Pure Infrastructure as Code (IaC) repository for provisioning an enterprise-grade, highly available, multi-tier decoupled WordPress stack on Amazon Web Services (AWS) in `ap-south-1` (Mumbai).

---

## 🏛️ High-Level Architecture Overview

```text
                                  Internet (0.0.0.0/0)
                                           │
                                           ▼ HTTPS (443) / HTTP (80)
                         [ Application Load Balancer (ALB) ]
                         (Multi-AZ: ap-south-1a & ap-south-1b)
                         (Security Group: wp-lab-alb-sg)
                                           │
                                           ▼ Port 80 (Chained Security Group)
                      [ Auto Scaling EC2 WordPress Web Fleet ]
                      (Stateless Compute Tier - No Local Database)
                      (Security Group: wp-lab-web-sg | Port 22 SSH ELIMINATED)
                                           │
                     ┌─────────────────────┴─────────────────────┐
                     │ Port 3306 (MySQL)                         │ Port 6379 (Redis)
                     ▼                                           ▼
         [ Amazon RDS MySQL 8.0 ]                     [ ElastiCache Redis 7.x ]
       (Private Subnets: 10.0.11.0/24)              (Private Subnets: 10.0.12.0/24)
       (SG: wp-lab-db-sg <- web-sg only)            (SG: wp-lab-redis-sg <- web-sg only)
                     │
                     ▼ Media Uploads (IAM Role / Zero Keys)
       [ Amazon S3 Media Bucket ] <──── [ Amazon CloudFront CDN (OAC) ]
```

---

## 📂 Comprehensive File-by-File Code Explanation

Every file in this repository is strictly modularized following HashiCorp standard conventions:

```text
aws-wordpress-infra/
├── .github/workflows/
│   └── terraform.yml       # Passwordless GitOps CI/CD pipeline via AWS IAM OIDC
├── .gitignore              # Ignores sensitive state files, lock files, and local binaries
├── provider.tf             # Terraform binary requirements, AWS Provider & S3 Remote State
├── variables.tf            # Parameterized CIDR blocks, regions, environments, and tags
├── vpc.tf                  # Step 1: Multi-AZ Custom VPC, Subnets, IGW, and Route Tables
├── security-groups.tf      # Step 2: 4 Chained Firewalls (ALB, Web, DB, Redis)
├── outputs.tf              # Exported resource IDs consumed by downstream tiers
├── install.sh              # EC2 cloud-init bootstrap script (Nginx, PHP, WordPress)
└── README.md               # Repository documentation and architectural guide
```

---

### 1. `provider.tf` — Foundation & Remote State Backend
- **Role:** Connects Terraform to AWS APIs, locks engine versions, and stores infrastructure state securely in the cloud.
- **Key Code Blocks:**
  1. `required_version = ">= 1.5.0"`: Enforces modern Terraform HCL2 syntax and prevents older CLI versions from running.
  2. `required_providers { aws = { version = "~> 5.0" } }`: Pins AWS Provider to version 5.x, allowing minor bugfixes while blocking breaking major upgrades (v6.x).
  3. `backend "s3"`:
     - `bucket = "wp-lab-tfstate-538820337783"`: Stores `terraform.tfstate` centrally in S3 so GitHub Actions runners and team members share one single source of truth.
     - `dynamodb_table = "wp-lab-tf-locks"`: Provides distributed state locking using DynamoDB. If two jobs run simultaneously, one is locked out to prevent state corruption.
     - `encrypt = true`: Enforces AES-256 server-side encryption at rest.
  4. `provider "aws"` + `default_tags`: Automatically applies tags (`Project = "wp-lab"`, `Environment = "lab"`, `ManagedBy = "Terraform"`) to **every single resource**, fulfilling Phase 11 AWS Cost Explorer tracking requirements.

---

### 2. `variables.tf` — Parameterized Input Variables
- **Role:** Eliminates hardcoded values across the codebase, allowing easy environment replication (e.g., dev, staging, prod) by changing variables.
- **Key Code Blocks:**
  1. `aws_region`: Target region, defaulting to `ap-south-1` (Mumbai).
  2. `project_name` & `environment`: Prefixes for naming resources (`wp-lab`, `lab`).
  3. `vpc_cidr`: Master network block (`10.0.0.0/16` = 65,536 private IP addresses).
  4. `public_subnet_1_cidr` (`10.0.1.0/24`) & `public_subnet_2_cidr` (`10.0.2.0/24`): Dual public subnets across Availability Zones `ap-south-1a` and `ap-south-1b` for ALB High Availability.
  5. `private_subnet_1_cidr` (`10.0.11.0/24`) & `private_subnet_2_cidr` (`10.0.12.0/24`): Dual isolated private subnets for RDS MySQL and ElastiCache Redis.

---

### 3. `vpc.tf` — Step 1: Isolated Networking Tier
- **Role:** Provisions the virtual private network and partitions it into public and private security zones across multiple datacenters.
- **Key Code Blocks:**
  1. `aws_vpc.main`: Isolated custom VPC (`10.0.0.0/16`). `enable_dns_hostnames = true` ensures EC2 and RDS instances receive internal AWS DNS endpoints.
  2. `aws_subnet.public_1` & `aws_subnet.public_2`: Public subnets across 2 AZs with `map_public_ip_on_launch = true`. Hosts the public-facing ALB.
  3. `aws_subnet.private_1` & `aws_subnet.private_2`: Private subnets across 2 AZs with `map_public_ip_on_launch = false`. Completely unreachable from the public internet; hosts database and cache instances.
  4. `aws_internet_gateway.gw`: The virtual doorway connecting the VPC to the internet.
  5. `aws_route_table.public` & `aws_route_table_association`: Route `0.0.0.0/0 -> aws_internet_gateway.gw.id`. What makes a subnet "Public" is this explicit route pointing to an Internet Gateway!

---

### 4. `security-groups.tf` — Step 2: Chained Hypervisor Firewalls
- **Role:** Enforces zero-trust defense-in-depth perimeter security using **Security Group Chaining** (referencing SG IDs instead of vulnerable IP CIDRs).
- **Key Code Blocks:**
  1. `aws_security_group.alb` (`wp-lab-alb-sg`):
     - Inbound: Port 80 (HTTP) & Port 443 (HTTPS) open to `0.0.0.0/0` (Global Internet).
     - Outbound: All traffic (`-1`) to forward requests to web instances.
  2. `aws_security_group.web` (`wp-lab-web-sg`):
     - Inbound: Port 80 **ONLY from `aws_security_group.alb.id`** (`security_groups = [aws_security_group.alb.id]`). Public internet CANNOT access web instances directly!
     - Inbound: **Port 22 (SSH) is completely removed!** Management is performed via AWS SSM Session Manager.
     - Outbound: Open to `0.0.0.0/0` for SSM agent, S3 uploads, and Ubuntu security patches.
  3. `aws_security_group.db` (`wp-lab-db-sg`):
     - Inbound: Port 3306 (MySQL) **ONLY from `aws_security_group.web.id`**.
     - Outbound: None. Database never initiates outbound connections.
  4. `aws_security_group.redis` (`wp-lab-redis-sg`):
     - Inbound: Port 6379 (Redis) **ONLY from `aws_security_group.web.id`**.
     - Outbound: None. In-memory cache never initiates outbound connections.

---

### 5. `outputs.tf` — Exported Return Values
- **Role:** Functions like return values in programming. Exposes provisioned AWS IDs so downstream modules (RDS, ALB, EC2, CloudFront) can dynamically bind to them without hardcoding.
- **Key Outputs:**
  - `vpc_id` & `vpc_cidr_block`
  - `public_subnet_ids` (List of both public subnets for ALB)
  - `private_subnet_ids` (List of both private subnets for RDS DB Subnet Group)
  - `alb_security_group_id`, `web_security_group_id`, `db_security_group_id`, `redis_security_group_id`

---

### 6. `install.sh` — Cloud-Init Web Bootstrap Script
- **Role:** Automated user-data bash script that runs automatically on the first boot of any new EC2 instance in the Auto Scaling Group.
- **Key Stages:**
  1. Creates 2GB swap space (`/swapfile`) to prevent out-of-memory crashes on `t3.micro`.
  2. Installs Nginx, PHP-FPM, PHP extensions (`php-mysql`, `php-gd`, `php-xml`, `php-zip`, etc.), and MySQL client non-interactively.
  3. Downloads and extracts latest official WordPress release to `/var/www/html`.
  4. Configures Nginx virtual host with FastCGI socket proxying to PHP-FPM.
  5. Configures ownership (`www-data:www-data`) and permissions (`755` directories, `644` files, `640` `wp-config.php`).

---

### 7. `.github/workflows/terraform.yml` — Passwordless GitOps Pipeline
- **Role:** Continuous Integration and Continuous Deployment (CI/CD) engine powered by GitHub Actions.
- **Key Workflow Features:**
  1. **Passwordless AWS IAM OIDC (`aws-actions/configure-aws-credentials`):** Authenticates to AWS using short-lived cryptographically signed GitHub JWT tokens. **Zero static `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` are stored in GitHub Secrets!**
  2. **Automated Dry Run on Pull Request (`terraform plan`):** When code is pushed to a PR, it validates HCL syntax and generates a detailed dry run so engineers can review planned changes before touching AWS.
  3. **Automated Deployment on Main Merge (`terraform apply -auto-approve`):** Automatically provisions the infrastructure once PR is merged into `main`.
  4. **Manual Teardown On-Demand (`workflow_dispatch` -> `destroy`):** Allows instant ₹0.00 cloud teardown from the GitHub UI to prevent idle cloud costs.

---

### 8. `.gitignore` — Version Control Protection
- **Role:** Prevents accidental commits of sensitive files to GitHub.
- **Protected Patterns:**
  - `**/.terraform/*`: Local provider plugins and engine caches.
  - `*.tfstate` & `*.tfstate.*`: Infrastructure state (kept safely in remote S3).
  - `*.tfvars`: Local secret parameter files.
  - `crash.log`: Debug crash logs.

---

## 🚀 Branching Model & GitOps Workflow

Following enterprise DevOps best practices, this repository uses a **Dev-to-Main GitOps flow**:
1. All local development happens on the **`dev`** branch:
   ```bash
   git checkout dev
   # write and test code...
   git commit -m "feat(infra): add step 3 IAM roles"
   git push origin dev
   ```
2. Open a Pull Request from `dev` into `main`.
3. GitHub Actions triggers `terraform plan` (Dry Run).
4. Upon approval and merge into `main`, GitHub Actions automatically runs `terraform apply`.
