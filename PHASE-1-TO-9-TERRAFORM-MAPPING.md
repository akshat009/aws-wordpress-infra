# 🗺️ Phase 1 to Phase 9 Manual ClickOps ➔ Terraform Modular IaC Translation Blueprint

> **Purpose:** This document provides the complete, line-by-line translation guide mapping every manual console action, CLI command, and architectural decision executed across Phases 1 through 9 into its corresponding modular Terraform HCL code block and target `.tf` file.

---

## 🧠 The Fundamental Architectural Shift: "Toy Monolith" vs "Production IaC"

### How We Built in Phases 1–9 (Console ClickOps):
In the learning phase, we started with a **monolithic toy server** and gradually dismantled it:
1. **Phase 1:** Launched a single EC2 in the Default VPC with local MySQL and local media storage.
2. **Phase 4:** Migrated the local database to an external Amazon RDS MySQL instance.
3. **Phase 5:** Offloaded local media files to an external Amazon S3 bucket behind CloudFront CDN.
4. **Phase 6:** Closed Port 22 (SSH) and attached an IAM Role for SSM Session Manager.
5. **Phase 8:** Added an in-memory ElastiCache Redis cluster for object caching.
6. **Phase 9:** Replaced the single EC2 with an Application Load Balancer (ALB) and Auto Scaling Fleet.

### How We Build in Terraform (Phase 10):
**In Terraform, we never provision the broken, intermediate toy states!**  
We directly codify and provision the **Final Decoupled, Zero-Trust, Highly Available Production Architecture** from day one:
- We never provision local MySQL on EC2.
- We never open Port 22 (SSH) in security groups.
- We never allow EC2 instances to store persistent state on disk.
- EC2 instances are 100% stateless compute workers that connect directly to RDS, Redis, S3, and CloudFront upon first boot.

---

## 📊 Master Translation Matrix: ClickOps ➔ Terraform

| Phase | Phase Domain | Manual Console / CLI Action (ClickOps) | Terraform Resource Equivalent | Target IaC File |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | **Compute & OS** | • EC2 Console -> Launch Instance (Ubuntu 24.04 `t3.micro`)<br>• Create & download `.pem` SSH key pair<br>• SSH into server: `ssh -i key.pem ubuntu@IP`<br>• Run `apt-get install nginx php-fpm`<br>• Download `wordpress.tar.gz` and extract to `/var/www/html` | • `data "aws_ami" "ubuntu"` (Dynamic AMI lookup)<br>• `install.sh` (Automated cloud-init user data script)<br>• `aws_launch_template.web` (`user_data = base64encode(...)`) | `compute-alb.tf`<br>`install.sh` |
| **Phase 2** | **Domain & HTTPS** | • Route 53 -> Create `A` record for `lab.asaxenadev.com`<br>• AWS Certificate Manager (ACM) -> Request public SSL cert<br>• Add CNAME DNS validation records in Route 53<br>• Bind ACM cert to ALB HTTPS:443 listener | • `aws_acm_certificate.cert`<br>• `aws_route53_record.cert_validation`<br>• `aws_acm_certificate_validation.cert`<br>• `aws_route53_record.wp_domain` (Alias A record pointing to ALB) | `route53.tf`<br>`compute-alb.tf` |
| **Phase 3** | **Deploy Pipeline** | • Create GitHub Actions workflow `.github/workflows/deploy.yml`<br>• Add SSH deploy secrets or AWS credentials to GitHub | • `.github/workflows/terraform.yml`<br>• `aws-actions/configure-aws-credentials@v4` with IAM OIDC (Zero static keys!) | `.github/workflows/terraform.yml` |
| **Phase 4** | **Decoupled Database** | • RDS Console -> Create Database -> MySQL 8.0 `db.t3.micro`<br>• Create DB Subnet Group across 2 Availability Zones<br>• Assign `wp-lab-db-sg` allowing Port 3306 from web server<br>• Stop local MySQL: `systemctl stop mysql`<br>• Update `wp-config.php` with RDS DNS endpoint | • `aws_db_subnet_group.main` (Private subnets)<br>• `aws_db_instance.wordpress` (`engine = "mysql"`, `instance_class = "db.t3.micro"`, `allocated_storage = 20`)<br>• `aws_security_group.db` (Port 3306 from `web-sg` only) | `rds.tf`<br>`security-groups.tf` |
| **Phase 5** | **Media Storage & CDN** | • S3 Console -> Create bucket `wp-lab-media-...`<br>• Block All Public Access (4 checkboxes checked)<br>• CloudFront Console -> Create Distribution with OAC<br>• Copy bucket policy banner from CloudFront and paste in S3<br>• Configure WP Offload SES/S3 plugin in WordPress | • `aws_s3_bucket.media`<br>• `aws_s3_bucket_public_access_block.media`<br>• `aws_cloudfront_origin_access_control.oac`<br>• `aws_cloudfront_distribution.s3_distribution`<br>• `aws_s3_bucket_policy.media` (Grants `s3:GetObject` to CloudFront distribution ARN only) | `s3-cloudfront.tf` |
| **Phase 6** | **Zero-Trust Hardening** | • Security Groups -> Delete Port 22 (SSH) Inbound rule<br>• IAM Console -> Create Role with `AmazonSSMManagedInstanceCore`<br>• Add inline policy for S3 media bucket upload/delete<br>• Attach IAM Role to EC2 instance<br>• Connect via AWS Systems Manager Session Manager shell | • `aws_security_group.web` (Zero port 22 ingress!)<br>• `aws_iam_role.ec2` (Trust relationship for `ec2.amazonaws.com`)<br>• `aws_iam_role_policy_attachment.ssm`<br>• `aws_iam_policy.s3_media` + attachment<br>• `aws_iam_instance_profile.ec2_profile` | `iam.tf`<br>`security-groups.tf` |
| **Phase 7** | **Email & Monitoring** | • Install CloudWatch Unified Agent on EC2 for memory/disk<br>• SNS Console -> Create Topic `wp-lab-alerts`<br>• Subscribe personal email address to SNS topic<br>• CloudWatch Alarms -> Create Alarm: Memory > 80% ➔ Send to SNS | • `aws_iam_role_policy_attachment.cloudwatch` (`CloudWatchAgentServerPolicy`)<br>• `aws_sns_topic.alerts`<br>• `aws_sns_topic_subscription.email`<br>• `aws_cloudwatch_metric_alarm.high_memory` | `monitoring.tf` / `iam.tf` |
| **Phase 8** | **In-Memory Caching** | • ElastiCache Console -> Create Redis cluster (`cache.t3.micro`)<br>• Create Cache Subnet Group in private subnets<br>• Assign `wp-lab-redis-sg` allowing Port 6379 from web server<br>• Install Redis PHP extension: `apt install php-redis`<br>• Connect Redis Object Cache plugin in WordPress | • `aws_elasticache_subnet_group.redis`<br>• `aws_elasticache_cluster.redis` (`engine = "redis"`, `node_type = "cache.t3.micro"`, `port = 6379`)<br>• `aws_security_group.redis` (Port 6379 from `web-sg` only) | `elasticache.tf`<br>`security-groups.tf` |
| **Phase 9** | **Scale & High Availability** | • EC2 Console -> Create Target Group (HTTP 80, path `/`)<br>• Create Application Load Balancer across 2 public subnets<br>• Create Launch Template with user_data and IAM Profile<br>• Create Auto Scaling Group (Min 1, Desired 2, Max 4)<br>• Add Target Tracking Scaling Policy (CPU Utilization 60%) | • `aws_lb.main` (Application Load Balancer across public subnets)<br>• `aws_lb_target_group.web`<br>• `aws_lb_listener.http`<br>• `aws_launch_template.web`<br>• `aws_autoscaling_group.web`<br>• `aws_autoscaling_policy.cpu_scaling` | `compute-alb.tf` |

---

## 🏗️ The 7-Step Dependency Execution Pipeline

Terraform requires resources to be created in strict dependency order. Here is how our modular codebase executes:

```text
Step 1: vpc.tf
        ├── Creates Master VPC (10.0.0.0/16)
        ├── Creates 2 Public Subnets (10.0.1.0/24, 10.0.2.0/24) for ALB
        ├── Creates 2 Private Subnets (10.0.11.0/24, 10.0.12.0/24) for RDS & Redis
        ├── Creates Internet Gateway (IGW)
        └── Creates Public Route Table & Subnet Associations
        │
        ▼
Step 2: security-groups.tf
        ├── wp-lab-alb-sg: Global Internet (Port 80/443 from 0.0.0.0/0)
        ├── wp-lab-web-sg: Chained strictly to ALB SG (Port 80 from alb-sg only | Port 22 SSH ELIMINATED)
        ├── wp-lab-db-sg: Chained strictly to Web SG (Port 3306 from web-sg only)
        └── wp-lab-redis-sg: Chained strictly to Web SG (Port 6379 from web-sg only)
        │
        ▼
Step 3: iam.tf
        ├── wp-lab-ec2-role: Assumed by ec2.amazonaws.com
        ├── Policy Attachment: AmazonSSMManagedInstanceCore (Port 22 SSH replacement)
        ├── Policy Attachment: CloudWatchAgentServerPolicy (Memory & Disk metrics)
        ├── Custom Policy: S3 Media Bucket Least-Privilege Read/Write
        └── wp-lab-ec2-instance-profile: Bridge container attaching role to EC2
        │
        ▼
Step 4: rds.tf + elasticache.tf
        ├── aws_db_subnet_group.main: Spans private subnets across 2 AZs
        ├── aws_db_instance.wordpress: MySQL 8.0 db.t3.micro in private subnets
        ├── aws_elasticache_subnet_group.redis: Spans private subnets
        └── aws_elasticache_cluster.redis: Redis 7.x cache.t3.micro
        │
        ▼
Step 5: s3-cloudfront.tf
        ├── aws_s3_bucket.media: Dedicated WordPress uploads bucket
        ├── aws_s3_bucket_public_access_block: Blocks 100% public access
        ├── aws_cloudfront_origin_access_control.oac: Cryptographic origin auth
        ├── aws_cloudfront_distribution.s3_distribution: Edge CDN caching
        └── aws_s3_bucket_policy: Grants access exclusively to CloudFront OAC
        │
        ▼
Step 6: compute-alb.tf
        ├── aws_lb.main: Application Load Balancer in public subnets
        ├── aws_lb_target_group.web: Health check monitoring on HTTP:80 /
        ├── aws_launch_template.web: Stateless Ubuntu 24.04 + install.sh + IAM Profile + web-sg
        ├── aws_autoscaling_group.web: Multi-AZ fleet (Min 1, Desired 2, Max 4)
        └── aws_autoscaling_policy: Dynamic scaling based on CPU demand
        │
        ▼
Step 7: route53.tf
        ├── aws_acm_certificate: Free managed SSL certificate
        ├── aws_route53_record (DNS validation): Validates domain ownership
        └── aws_route53_record (Alias A): Points lab.asaxenadev.com -> ALB DNS name
```

---

## ⚡ What Happens When We Run `terraform apply`?

Instead of clicking 150+ buttons across 9 different AWS console services over several weeks:
1. Developer pushes code to `dev` branch and opens a Pull Request.
2. GitHub Actions runs `terraform plan` (Dry Run verification).
3. Pull Request is approved and merged into `main`.
4. GitHub Actions executes `terraform apply -auto-approve`.
5. **Within 4–6 minutes, AWS automatically builds the entire decoupled, highly available, production-grade WordPress cloud stack from scratch!**
