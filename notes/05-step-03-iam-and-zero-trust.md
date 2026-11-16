# 🔐 Step 3: Zero-Trust IAM Identity, SSM Session Manager & Instance Profile

> **File:** `iam.tf`  
> **Architecture Level:** Tier 3 — Identity & Access Management (IAM)  
> **Security Mandate:** Zero Static Keys, Zero Inbound Management Ports, Strict Least Privilege

---

## 🧠 Why Does Compute Need an IAM Role?

In traditional (and insecure) cloud setups, developers configure static AWS Access Keys (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) inside servers (e.g. `~/.aws/credentials` or `.env` files) so the application can interact with AWS services like Amazon S3.

**The Danger:**
* If the web server or WordPress has a remote code execution (RCE) vulnerability, attackers dump the credentials and compromise the entire AWS account.
* Keys never rotate automatically and are frequently leaked to public Git repositories.

**The Solution in Step 3:**
We attach an **AWS IAM Role (`wp-lab-ec2-role`)** directly to the EC2 instances via an **IAM Instance Profile (`wp-lab-ec2-instance-profile`)**.
* The instance retrieves short-lived, automatically rotating STS credentials from the EC2 Instance Metadata Service (IMDSv2 at `http://169.254.169.254/latest/meta-data/iam/security-credentials/`).
* **Zero static API keys ever touch the server's disk!**

---

## 🛠️ Step 3 Components Breakdown

### 1. `aws_iam_role.ec2` — Assume Role Trust Policy
Allows the AWS EC2 service to assume this identity:
```hcl
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
```

---

### 2. `aws_iam_role_policy_attachment.ssm` — The SSH Killer (Port 22 Eliminated)
* **Policy ARN:** `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore`
* **Why this is critical:**
  * In Phase 6 (Zero-Trust Hardening), we permanently deleted Port 22 (SSH) from our security groups.
  * Without Port 22 open, how do administrators connect to debug or inspect the server?
  * The Ubuntu Amazon SSM Agent runs inside the instance and maintains an **outbound HTTPS (Port 443)** polling tunnel to AWS Systems Manager endpoints.
  * Administrators connect directly via the AWS Management Console browser terminal or AWS CLI:
    ```bash
    aws ssm start-session --target <i-instanceid>
    ```
  * **Result:** Zero open listening ports exposed to the public internet! 100% immune to SSH brute force attacks.

---

### 3. `aws_iam_role_policy_attachment.cloudwatch` — OS Metrics & Telemetry
* **Policy ARN:** `arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy`
* **Why this is required:**
  * By default, the AWS hypervisor can only see physical metrics from the outside (CPU Utilization, Network In/Out, Disk Read/Write Ops).
  * The hypervisor **cannot** see internal OS memory (RAM) or disk space used because of hypervisor memory isolation.
  * In Phase 7, the CloudWatch Unified Agent was installed on Ubuntu. This IAM policy authorizes the agent to push RAM utilization (`mem_used_percent`), disk space (`disk_used_percent`), and Nginx/PHP error logs directly to CloudWatch Metrics and CloudWatch Logs.

---

### 4. `aws_iam_policy.s3_media` — WordPress S3 Least Privilege
* In Phase 5, WordPress offloads images and media uploads (`/wp-content/uploads/`) to an Amazon S3 bucket.
* Instead of giving `s3:*` (Full Admin Access), this custom IAM policy grants only:
  * `s3:PutObject` (Upload media)
  * `s3:GetObject` (Read media)
  * `s3:DeleteObject` (Delete media when removed from WordPress)
  * `s3:ListBucket` (Browse uploads directory)
* Restricted strictly to buckets prefixed with `arn:aws:s3:::wp-lab-media-*`.

---

### 5. `aws_iam_instance_profile.ec2` — The Container Bridge
In AWS, an IAM Role cannot be directly attached to an EC2 instance or Auto Scaling Launch Template. AWS requires an **Instance Profile**, which acts as an IAM container that encapsulates the role:

```text
[ IAM Role: wp-lab-ec2-role ]
             │ (Contains Policies: SSM + CloudWatch + S3)
             ▼
[ IAM Instance Profile: wp-lab-ec2-instance-profile ]
             │ (Referenced in Step 6 Launch Template)
             ▼
[ EC2 Fleet Instances ]
```

---

## 📊 Summary of Step 3 Outputs

| Output Variable | Value / Description |
| :--- | :--- |
| `ec2_iam_role_name` | `wp-lab-ec2-role` |
| `ec2_iam_role_arn` | `arn:aws:iam::<account-id>:role/wp-lab-ec2-role` |
| `ec2_instance_profile_name` | `wp-lab-ec2-instance-profile` |
| `ec2_instance_profile_arn` | `arn:aws:iam::<account-id>:instance-profile/wp-lab-ec2-instance-profile` |
