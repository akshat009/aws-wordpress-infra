# 📚 Architecture, Discussions & Engineering Notes

Welcome to the **Engineering Notes & Discussion Repository** for `aws-wordpress-infra`. This directory logs all architectural designs, troubleshooting retrospectives, Q&A discussions, and implementation blueprints developed throughout this project.

---

## 📑 Table of Contents

| File | Category | Summary |
| :--- | :--- | :--- |
| **[`01-phase-1-to-9-terraform-mapping.md`](01-phase-1-to-9-terraform-mapping.md)** | **Master Blueprint** | Complete line-by-line translation guide mapping all manual AWS Console actions (Phases 1–9) to modular Terraform HCL. |
| **[`02-step-01-and-02-networking-and-security.md`](02-step-01-and-02-networking-and-security.md)** | **Deep Dive** | Detailed breakdown of Step 1 (VPC, Multi-AZ Subnets, IGW, Route Tables) and Step 2 (Security Group Chaining, Zero-Trust). |
| **[`03-oidc-aws-iam-setup.md`](03-oidc-aws-iam-setup.md)** | **DevSecOps / CI/CD** | Root cause analysis and step-by-step resolution for GitHub Actions passwordless OIDC authentication (`sts:AssumeRoleWithWebIdentity`). |
| **[`04-static-ip-vs-alb-dns.md`](04-static-ip-vs-alb-dns.md)** | **Architecture Q&A** | Comprehensive explanation of why modern production systems replace Static Elastic IPs (EIP) with dynamic ALB DNS endpoints and Route 53 aliases. |
| **[`05-step-03-iam-and-zero-trust.md`](05-step-03-iam-and-zero-trust.md)** | **Deep Dive** | Step 3 deep dive: IAM Role for EC2, SSM Session Manager (SSH elimination), CloudWatch Unified Agent, S3 media least privilege, and Instance Profile. |

---

## 🗺️ Architectural Road Map

```text
Step 1: Isolated VPC & Multi-AZ Subnets (Completed)
   │
   ▼
Step 2: Chained Security Groups & Zero-Trust Perimeter (Completed)
   │
   ▼
Step 3: IAM Roles & SSM Session Manager (Next)
   │
   ▼
Step 4: Managed Database (Amazon RDS MySQL) & In-Memory Cache (ElastiCache Redis)
   │
   ▼
Step 5: Media Storage (Amazon S3) & Edge Caching (CloudFront CDN + OAC)
   │
   ▼
Step 6: Elastic Compute (Application Load Balancer + Auto Scaling Fleet)
   │
   ▼
Step 7: DNS & SSL (Route 53 Hosted Zone + AWS Certificate Manager ACM)
```

---

> 💡 **Tip:** Whenever you make new architectural changes or resolve operational bugs, create a new numbered `.md` file in this directory and link it here to keep your project documentation 100% production-ready.
