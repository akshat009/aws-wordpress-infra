# ==============================================================================
# File: iam.tf
# Tier: Step 3 - Zero-Trust Identity, Session Manager & Instance Profile
# Description: Provisions the IAM Role, Instance Profile, and least-privilege
#              policy attachments for EC2 instances. Eliminates Port 22 (SSH)
#              in favor of AWS Systems Manager (SSM) Session Manager, grants
#              CloudWatch Unified Agent permissions, and authorizes S3 media uploads.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. EC2 Assume Role Trust Policy
# ------------------------------------------------------------------------------
# In Phase 6, we learned that EC2 instances should never possess static AWS API keys.
# Instead, the instance assumes a temporary IAM Role directly via AWS STS metadata service.
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

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# ------------------------------------------------------------------------------
# 2. AWS Systems Manager (SSM) Policy Attachment
# ------------------------------------------------------------------------------
# Why AmazonSSMManagedInstanceCore?
# In Phase 6 (Zero-Trust Hardening), we completely deleted Port 22 (SSH) inbound rules.
# This policy allows the EC2 instance to communicate with the AWS Systems Manager service
# over outbound HTTPS (Port 443). Administrators connect to server terminals directly
# from the AWS Console or AWS CLI (`aws ssm start-session`) without opening any inbound ports!
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ------------------------------------------------------------------------------
# 3. CloudWatch Unified Agent Policy Attachment
# ------------------------------------------------------------------------------
# In Phase 7 (Monitoring & Observability), we installed the CloudWatch agent.
# By default, AWS EC2 hypervisors cannot see internal OS metrics like RAM usage or disk space.
# This policy allows the CloudWatch Agent on Ubuntu to push custom RAM, disk, and swap metrics
# as well as Nginx/PHP error logs directly to Amazon CloudWatch.
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ------------------------------------------------------------------------------
# 4. Custom Least-Privilege Policy: S3 Media Storage
# ------------------------------------------------------------------------------
# In Phase 5, WordPress offloads media uploads (/wp-content/uploads) to an Amazon S3 bucket.
# Instead of granting full S3 admin access, this policy adheres strictly to the Principle
# of Least Privilege: instances can only read, write, and delete files inside wp-lab-media buckets.
resource "aws_iam_policy" "s3_media" {
  name        = "${var.project_name}-s3-media-policy"
  description = "Grants EC2 WordPress web servers least-privilege access to media uploads S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-media-*",
          "arn:aws:s3:::${var.project_name}-media-*/*"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-s3-media-policy"
  }
}

resource "aws_iam_role_policy_attachment" "s3_media" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.s3_media.arn
}

# ------------------------------------------------------------------------------
# 5. IAM Instance Profile (Bridge Container)
# ------------------------------------------------------------------------------
# In AWS, an IAM Role cannot be attached directly to an EC2 instance.
# AWS requires an "Instance Profile", which acts as an IAM container that holds the role.
# In Step 6, this instance profile will be referenced inside aws_launch_template.web.
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2.name

  tags = {
    Name = "${var.project_name}-ec2-instance-profile"
  }
}
