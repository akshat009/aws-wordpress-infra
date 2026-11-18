# AWS WordPress Infrastructure (Terraform)

Infrastructure as Code for WordPress on AWS (`ap-south-1`, Mumbai). One codebase, three architecture modes, switched by a single Terraform variable:

| `architecture_mode` | What runs | Approx. cost |
| :--- | :--- | :--- |
| `standalone` (default) | 1 EC2 + local MySQL + Elastic IP + Let's Encrypt | ~$0 on Free Tier, ~$12/month after |
| `migrating` | Standalone keeps serving **plus** RDS and the ACM certificate (used while moving data) | standalone + RDS |
| `enterprise` | ALB + Auto Scaling Group (2 AZs) + RDS MySQL 8.4 + ACM (TLS 1.3) | ~$65–75/month on-demand |

These layers are on in every mode: custom VPC, chained security groups, SSM instead of SSH, private S3 media behind CloudFront (OAC), secrets in SSM Parameter Store, CloudWatch alarms, a monthly budget alert and keyless GitHub Actions (OIDC).

Prices are rough on-demand estimates; check the AWS Pricing Calculator.

---

## Architecture

```text
                         Internet
                            │
          ┌─────────────────┴──────────────────┐
   standalone / migrating                  enterprise
          │                                     │
   Elastic IP (A record)              ALB :80→301, :443 TLS 1.3 (CNAME)
          │                                     │  port 80 from alb-sg only
   EC2 (Nginx, PHP, MySQL)            Auto Scaling Group (1–4 × EC2, 2 AZs)
          │                                     │  CPU target tracking
          │                                     ▼
          │                          RDS MySQL 8.4 (private subnets, encrypted)
          │                                     ▲
          └──── migrating: both exist ──────────┘  (migrate-database.yml copies data)

   Always on: S3 media ← CloudFront (OAC) · SSM Parameter Store (DB password)
              S3 artifacts (app releases) · SNS alerts · CloudWatch alarms · AWS Budget
```

Servers sit in public subnets, locked down by security groups, instead of private subnets behind a NAT gateway. This is a deliberate cost trade-off: each NAT gateway costs ~$33–45/month.

---

## Repository layout

```text
.
├── provider.tf          Terraform + provider versions, S3 backend with DynamoDB lock (values passed at init)
├── backend.hcl.example  terraform.tfvars.example   Laptop-only settings templates (copies are git-ignored)
├── variables.tf         All settings. architecture_mode switch is at the top
├── locals.tf            Turns architecture_mode into run_standalone / run_rds / run_fleet flags
├── vpc.tf               VPC, 2 public + 2 private subnets, IGW, route tables
├── security-groups.tf   ALB, web, DB and Redis security groups (web rules follow the mode)
├── iam.tf               EC2 role: SSM, CloudWatch, S3 media, DB password + releases (read-only)
├── secrets.tf           Generated DB password stored as an SSM SecureString
├── compute-alb.tf       Standalone EC2 + EIP, or ALB + launch template + ASG + scaling policy
├── rds.tf               RDS MySQL 8.4 (encrypted, 7-day backups, final snapshot)
├── ssl.tf               ACM certificate (requested in migrating) + HTTPS listener (enterprise)
├── s3-cloudfront.tf     Media bucket (versioned) + CloudFront OAC; artifacts bucket
├── monitoring.tf        SNS topic, email subscription, CloudWatch alarms per mode
├── budget.tf            Monthly budget: alerts at 80% actual and 100% forecast
├── backup.tf            AWS Backup daily plan (off by default: enable_backups)
├── outputs.tf           Endpoints and IDs; mode-specific outputs return null when off
├── install.sh           First-boot setup for every server (reads password from SSM)
├── tests/               Offline terraform tests for every mode (mocked AWS)
├── scripts/migrate-db.sh                 Local MySQL ⇄ RDS migration (runs via SSM); backs up both sides to S3 first
├── .github/scripts/configure-domain.py   Rebuilds wp-config.php during deploys
├── .github/scripts/nginx-site.sh         Nginx site for the single server: works directly and behind the ALB
├── .github/scripts/ssm-run.sh            Runs commands on a server through SSM and waits (used by workflows)
├── .github/workflows/
│   ├── terraform.yml          fmt, validate, test, Checkov scan, plan → approved apply
│   ├── deploy-app.yml         wp-content → S3 release + SSM deploy to all servers
│   ├── install-ssl.yml        Let's Encrypt (no ALB) or ACM check (ALB) + ALB-ready Nginx site
│   ├── scripts-test.yml       Tests nginx-site.sh on a real Nginx (PRs touching .github/scripts)
│   └── migrate-database.yml   One-click local-to-rds / rds-to-local
└── wp-content/          Theme and plugins deployed by deploy-app.yml
```

---

## One-time setup

**Day 0 (AWS console, once):** S3 state bucket, DynamoDB lock table (`LockID`), GitHub OIDC provider and `GitHubActionsTerraformRole`. Terraform can't create its own backend.

**GitHub repository settings (Day 0, before the first workflow run):**

#### Repository variables

Settings → Secrets and variables → Actions → **Variables**. **Required**: every workflow checks them first (`.github/scripts/check-vars.sh`) and stops with a clear error if one is missing. **The code has no project-specific values or fallbacks**: CI passes these to Terraform (`TF_VAR_aws_region`, `TF_VAR_project_name`, `TF_VAR_domain_name`, and `-backend-config` for the state), so Terraform, the workflows and the scripts always use the same values.

| Variable | Value | Used for |
| :--- | :--- | :--- |
| `AWS_REGION` | e.g. `ap-south-1` | Region of every resource and every AWS CLI call |
| `PROJECT_NAME` | e.g. `wp-lab` | Prefix of every resource name; workflows find servers, buckets, RDS and the SSM password (`/<PROJECT_NAME>/db/password`) by it |
| `DOMAIN_NAME` | e.g. `lab.asaxenadev.com` | Site address: certificate, `wp-config.php`, smoke tests |
| `AWS_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/GitHubActionsTerraformRole` | The role GitHub Actions assumes through OIDC |
| `TF_STATE_BUCKET` | e.g. `wp-lab-tfstate-<ACCOUNT_ID>` | Terraform state bucket (Day 0). Must be in `AWS_REGION` |
| `TF_LOCK_TABLE` | e.g. `wp-lab-tf-locks` | DynamoDB lock table (Day 0, partition key `LockID`) |

> **Choose `AWS_REGION` and `PROJECT_NAME` once, at Day 0.** Changing either later means Terraform renames or moves **every** resource (a rebuild). Name the state bucket and lock table to match (`<PROJECT_NAME>-tfstate-<ACCOUNT_ID>`, `<PROJECT_NAME>-tf-locks`).

#### Secret and environment

| Setting | Where | Value |
| :--- | :--- | :--- |
| `ALERT_EMAIL` | Settings → Secrets and variables → Actions → **Secrets** (masked as `***` in logs; a variable would print it publicly) | Email for alarms, budget alerts and Let's Encrypt |
| Approval gate | Settings → Environments → `production` → Required reviewers | Add yourself |

Without `ALERT_EMAIL` no email subscription is created. After the first apply, AWS sends a confirmation email that you must click.

---

## Day-to-day flow

1. Branch → change code → open a PR into `main`.
2. `terraform.yml` runs `fmt`, `validate`, `terraform test`, a Checkov scan and `plan`. The plan summary appears on the run page, with a warning if anything would be deleted or replaced.
3. Merge → plan runs again → the **apply** job waits for approval in the `production` environment → apply → smoke test against the new endpoint.
4. Changes under `wp-content/` trigger `deploy-app.yml`. It publishes the release to S3 (for servers launched later) and deploys to every running server through SSM.

---

## Switching architecture modes

Change one line in [`variables.tf`](variables.tf) (`architecture_mode` → `default`) and merge. Always go through `migrating`; it's the only stage where both databases exist.

### Upgrade: standalone → enterprise

1. **`architecture_mode = "migrating"`** → merge. RDS and the ACM certificate are created; the site keeps running on the standalone server.
2. Add the CNAME from the `acm_dns_validation_records` output to Hostinger DNS.
3. Make sure every plugin you installed from WP admin is committed in `wp-content/plugins/`. Plugins on a server's disk don't reach new servers.
4. Copy any media that isn't in S3 yet (uploads made before WP Offload Media was set up) into the media bucket.
5. Run **Universal Database Migration** → `local-to-rds`. The standalone server now uses RDS.
6. **`architecture_mode = "enterprise"`** → merge. The ALB, ASG and HTTPS listener are created and the standalone server is deleted. Its data is already in RDS.
7. Hostinger: replace the `lab` A record with the CNAME shown in the `dns_instructions` output.
8. Run **Deploy WordPress Application Code** once. Optionally run **Universal SSL Certificate Automation** to confirm ACM shows *Issued*.

Expect a few minutes of downtime between step 6 and DNS propagation in step 7.

### Downgrade: enterprise → standalone

1. **`architecture_mode = "migrating"`** → merge. The ALB and ASG are removed and a fresh standalone server is created with an empty local database. **The site is down from here until step 3.**
2. Run **Universal Database Migration** → `rds-to-local`.
3. Hostinger: point the `lab` A record at the `dns_instructions` IP, then run **Universal SSL Certificate Automation**.
4. **`architecture_mode = "standalone"`** → merge. RDS is deleted after a final snapshot (`wp-lab-db-final-*`). Delete old snapshots by hand when you no longer need them, because they cost money.

If `rds_deletion_protection = true`, set it to `false` before step 4.

---

## Turning features on individually

`architecture_mode` is a **preset**. Each feature can also be switched on/off on its own in `variables.tf`; a switch left at `null` follows the preset.

| Switch | Default | Turns on/off |
| :--- | :--- | :--- |
| `enable_rds` | preset | Amazon RDS (MySQL 8.4) |
| `enable_alb` | preset | Application Load Balancer + ACM certificate + HTTPS listener. Works in front of the **single server** too |
| `enable_asg` | preset | Auto Scaling fleet (replaces the single server). **Requires `enable_alb` and `enable_rds`** |
| `enable_alarms` | `true` | CloudWatch alarms (the SNS topic always exists) |
| `enable_budget` | `true` | Monthly budget alerts |
| `enable_backups` | `false` | Daily AWS Backup (tag `Backup = daily`) |

| Combination | How |
| :--- | :--- |
| 1 server + local MySQL | `architecture_mode = "standalone"` |
| 1 server + **RDS**, no load balancer | `standalone` + `enable_rds = true`, then run **Universal Database Migration** `local-to-rds` |
| **Load balancer** in front of 1 server, local MySQL | Run **Universal SSL Certificate Automation** once first (makes the server's Nginx ALB-ready), then `standalone` + `enable_alb = true`; DNS → `CNAME` to the ALB (see `dns_instructions`) |
| Load balancer + 1 server + RDS | `standalone` + `enable_alb = true` + `enable_rds = true` |
| Full enterprise (fleet) | `architecture_mode = "enterprise"` |
| Fleet **without** RDS or ALB | **Rejected at plan time** (`terraform_data.feature_rules`): servers in a fleet must share one database |

**Why run the SSL workflow before `enable_alb` on a server that has Let's Encrypt:** `certbot --redirect` made port 80 answer `301` for everything, but the ALB talks to the server on port 80, so its health check would fail and visitors would loop. The workflow rewrites the Nginx site so port 80 serves the ALB (requests with `X-Forwarded-Proto: https`) and `/health.html`, while direct HTTP visitors are still redirected to HTTPS.

A new standalone server always installs local MySQL, but points WordPress at RDS when `enable_rds` is on, so it never starts with an empty database.

## Security model

- **No SSH:** port 22 is closed; shell access and deploys go through SSM.
- **No static keys:** GitHub Actions uses OIDC; servers use an IAM role with IMDSv2 required.
- **No secrets in code or user data:** the DB password is generated by Terraform and stored in SSM Parameter Store. Servers and `migrate-db.sh` read it at runtime.
- **Least privilege:** the DB accepts 3306 only from `web-sg`; in enterprise mode `web-sg` accepts 80 only from `alb-sg`; the media bucket is readable only by its CloudFront distribution.
- **Encryption at rest:** S3 (SSE-S3), RDS, fleet root volumes, SSM SecureString.
- **Protection of the standalone server:** `ignore_changes = [ami, user_data]` stops accidental replacement. Deletion happens only through the deliberate mode switch, and only after plan review and approval.

---

## Testing locally

```bash
terraform init -backend=false
terraform test        # mocked AWS: checks every mode builds the right resources
terraform fmt -check -recursive
```

Tests need no AWS account and no settings (they pin their own values). To run a real `plan` on a laptop (CI normally does this), copy the two example files and fill them in; both copies are git-ignored:

```bash
cp backend.hcl.example backend.hcl            # state bucket, region, lock table
cp terraform.tfvars.example terraform.tfvars  # aws_region, project_name, domain_name
terraform init -backend-config=backend.hcl
terraform plan
```

---

## Known limitations / next steps

- ElastiCache Redis: only the security group exists.
- CloudWatch Agent (memory and disk metrics) is permitted by IAM but not installed.
- WP Offload Media bucket and CloudFront settings are still entered in WP admin.
- One AWS account and one environment; no WAF.
- The Terraform deploy role has broad permissions; scope it down for real production.
