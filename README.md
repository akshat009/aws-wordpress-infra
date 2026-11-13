# ☁️ AWS Decoupled WordPress Infrastructure (Terraform)

Pure Infrastructure as Code (IaC) repository for provisioning an enterprise-grade, highly available, multi-tier decoupled WordPress stack on Amazon Web Services (AWS) in `ap-south-1` (Mumbai).

---

## 🏛️ Architecture Overview

```text
                                Internet (0.0.0.0/0)
                                         │
                                         ▼ HTTPS (443) / HTTP (80)
                       [ Application Load Balancer (ALB) ]
                         (Multi-AZ: ap-south-1a & ap-south-1b)
                                         │
                                         ▼ Port 80 (Chained SG)
                    [ Auto Scaling EC2 WordPress Web Fleet ]
                     (Stateless Compute Tier - No Local DB)
                                         │
                   ┌─────────────────────┴─────────────────────┐
                   │ Port 3306 (MySQL)                         │ Port 6379 (Redis)
                   ▼                                           ▼
       [ Amazon RDS MySQL 8.0 ]                     [ ElastiCache Redis 7.x ]
     (Private Subnet Tier Multi-AZ)                 (Object Cache Subnets)
```

---

## 📂 Repository File Structure

- **`provider.tf`** — Terraform engine version pinning (`>= 1.5.0`), AWS Provider (`~> 5.0`), S3 remote state backend (`wp-lab-tfstate-...`), DynamoDB lock table (`wp-lab-tf-locks`), and default tags.
- **`variables.tf`** — Parameterized CIDR blocks (`10.0.0.0/16`, `/24` subnets), region, environment, and project tags.
- **`vpc.tf`** — Master Custom VPC, 2 Public Subnets, 2 Private Subnets, Internet Gateway (`aws_internet_gateway`), and Public Route Table.
- **`security-groups.tf`** — 4 Chained Security Groups (`alb-sg`, `web-sg`, `db-sg`, `redis-sg`) with zero public ingress to backend tiers and 100% elimination of Port 22 (SSH).
- **`outputs.tf`** — Exposes core VPC, Subnet, and Security Group identifiers for downstream tiers.
- **`install.sh`** — Automated cloud-init bootstrap script for web instances.
- **`.github/workflows/terraform.yml`** — Passwordless GitOps CI/CD pipeline authenticated via AWS IAM OIDC.

---

## 🚀 Deployment Workflow

Deployments are fully automated via GitHub Actions GitOps:
1. Pushing to branch `main` triggers automated `terraform plan` and `terraform apply`.
2. Teardown can be dispatched on-demand via `workflow_dispatch` with input `action: destroy`.
