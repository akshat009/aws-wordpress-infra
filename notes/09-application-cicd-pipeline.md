# 🚢 Step 3 (App Tier): Zero-Trust Application CI/CD Pipeline

> **Workflow:** `.github/workflows/deploy-app.yml`  
> **Source Directory:** `wp-content/`  
> **Target Fleet:** Dynamic EC2 instances in Auto Scaling Group (`wp-lab-asg*`)  
> **Deployment Mechanism:** AWS Systems Manager (SSM) Run Command (`AWS-RunShellScript`) via IAM OIDC

---

## 🧠 Why Traditional SSH Deployments Fail in Production

In Phase 3 of the manual ClickOps lab, developers typically deployed code using SSH (`appleboy/ssh-action` or `scp`):

### Why SSH Deployment is an Anti-Pattern:
1. **Requires Open Inbound Port 22:** Exposes virtual machines to internet-wide brute force attacks.
2. **Static Secrets Leaks:** Requires storing a private `.pem` SSH key in GitHub Secrets.
3. **Breaks with Auto Scaling:** You cannot hardcode an IP address when servers scale dynamically between 1 and 4 instances.
4. **Manual Flap:** If an instance terminates and ASG launches a new one, the new instance won't have the changes made via SSH.

---

## 🏗️ The Zero-Trust GitOps Application Deployment Flow

Instead of SSH, we use **AWS Systems Manager (SSM) Run Command** over outbound HTTPS:

```text
[ Developer Pushes to wp-content/** ]
                 │
                 ▼
[ GitHub Actions: deploy-app.yml ]
                 │
                 │ 1. Passwordless OIDC Authentication (Zero Keys)
                 ▼
[ AWS Security Token Service (STS) ]
                 │
                 │ 2. Discover running instances in Auto Scaling Group
                 ▼
[ AWS Systems Manager (SSM) Run Command ]
                 │
                 │ 3. Outbound HTTPS (Port 443) polling tunnel
                 ▼
[ EC2 Fleet Nodes (ap-south-1a & ap-south-1b) ]
                 ├── Extracts wp-content.tar.gz to /var/www/html/wp-content/
                 ├── Enforces www-data:www-data ownership
                 ├── Enforces 755 (dirs) / 644 (files) permissions
                 └── Gracefully reloads Nginx
```

---

## 🛠️ How to Use This Pipeline

### Trigger 1: Automatic Deploy on Git Push
Whenever you push changes inside the `wp-content/` folder (such as editing `wp-content/themes/wp-lab-theme/style.css`):
1. Commit and push to `main` (or via PR).
2. GitHub Actions triggers `deploy-app.yml` automatically.
3. Within ~30 seconds, all running EC2 instances are updated in parallel!

### Trigger 2: Manual Trigger (One-Click Deploy)
1. Go to the **Actions** tab in GitHub.
2. Select **"Deploy WordPress Application Code"**.
3. Click **"Run workflow"** ➔ **Run workflow**.

---

## 📂 Managed Code Structure

```text
aws-wordpress-infra/
├── .github/workflows/
│   ├── terraform.yml       # Infrastructure CI/CD (VPC, RDS, ALB, ASG)
│   └── deploy-app.yml      # Application CI/CD (WordPress themes & plugins)
├── wp-content/
│   └── themes/
│       └── wp-lab-theme/   # Custom production child theme
│           ├── style.css
│           └── index.php
└── notes/
    └── 09-application-cicd-pipeline.md
```
