# 🔐 AWS IAM OIDC Setup & Trust Policy Configuration Guide

> **Location:** `C:\Users\HP\Desktop\aws-wordpress-infra\OIDC-AWS-IAM-SETUP.md`  
> **Target Role:** `arn:aws:iam::538820337783:role/GitHubActionsTerraformRole`  
> **Security Standard:** Zero-Trust Passwordless Authentication via OpenID Connect (OIDC) & AWS Security Token Service (STS)

---

## 🧠 Why Does GitHub Actions Need an IAM Trust Policy?

In traditional (and insecure) CI/CD setups, developers store static `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in GitHub Secrets. If an action is compromised or a log leaks, the AWS account is compromised.

In our **Enterprise GitOps Architecture**, we use **AWS IAM OpenID Connect (OIDC)**:
1. When GitHub Actions runs, GitHub generates a short-lived cryptographically signed JSON Web Token (JWT).
2. The GitHub runner presents this JWT to **AWS Security Token Service (STS)** via the API call `sts:AssumeRoleWithWebIdentity`.
3. AWS inspects the JWT's claims (`iss`, `aud`, `sub`, `repository`).
4. If the claims match the **Trust Policy** on `GitHubActionsTerraformRole`, AWS grants a temporary, 15-minute STS session credential.
5. **Zero static keys exist on GitHub or your local disk!**

---

## 🚨 The Error: Why Did the Initial Pipeline Run Fail?

When GitHub Actions ran on `akshat009/aws-wordpress-infra`, it failed with:

```text
##[error]Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

### The Root Cause:
In Phase 10, the IAM Role `GitHubActionsTerraformRole` was configured to trust only the original repository (`akshat009/Aws-wp-lab`).  
Because this new repository is `akshat009/aws-wordpress-infra`, AWS STS rejected the request as untrusted!

Furthermore, GitHub Actions includes immutable numeric database IDs in the `sub` claim:
```json
{
  "iss": "https://token.actions.githubusercontent.com",
  "aud": "sts.amazonaws.com",
  "sub": "repo:akshat009@23046599/aws-wordpress-infra@1456475210:pull_request",
  "repository": "akshat009/aws-wordpress-infra"
}
```
Therefore, our IAM Trust Policy must use `StringLike` wildcard matching (`repo:akshat009*/aws-wordpress-infra*:*`) to match both branch pushes and pull requests seamlessly.

---

## 🛠️ Step-by-Step Fix in AWS Console (Takes 30 Seconds)

### Step 1: Open the IAM Role in AWS Console
1. Log into your **AWS Management Console** in `ap-south-1` (Mumbai).
2. In the top search bar, search for **`IAM`** and select **IAM (Identity and Access Management)**.
3. In the left navigation menu, click **Roles**.
4. In the search box, search for:
   ```text
   GitHubActionsTerraformRole
   ```
5. Click on the role name **`GitHubActionsTerraformRole`** to open its configuration.

---

### Step 2: Edit the Trust Policy
1. Select the **Trust relationships** tab (located next to Permissions).
2. Click the **Edit trust policy** button on the right.
3. Replace the entire JSON editor content with the following verified multi-repository trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::538820337783:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:akshat009*/aws-wordpress-infra*:*",
            "repo:akshat009/aws-wordpress-infra:*",
            "repo:akshat009@23046599/aws-wordpress-infra@1456475210:*",
            "repo:akshat009*/Aws-wp-lab*:*",
            "repo:akshat009/Aws-wp-lab:*"
          ]
        }
      }
    }
  ]
}
```

4. Click the orange **Update policy** button at the bottom right.

---

## 🔄 Step 3: Trigger Re-run & Merge Pull Request

Once the policy is saved in AWS Console:
1. Go to **Pull Request #1** on GitHub:
   👉 [https://github.com/akshat009/aws-wordpress-infra/pull/1](https://github.com/akshat009/aws-wordpress-infra/pull/1)
2. In the PR checks section, click **Re-run all checks** (or re-run from the Actions tab).
3. GitHub Actions will authenticate via OIDC in < 2 seconds.
4. It will run:
   - `terraform init` against S3 Backend (`wp-lab-tfstate-538820337783`)
   - `terraform validate`
   - `terraform plan` (Dry Run preview)
5. Review the plan output:
   ```text
   Plan: 9 to add, 0 to change, 0 to destroy.
   ```
6. Click **Merge pull request** ➔ **Confirm merge**.
7. GitHub Actions will automatically run `terraform apply` on branch `main` and provision Step 1 (VPC) & Step 2 (Security Groups) in AWS!
