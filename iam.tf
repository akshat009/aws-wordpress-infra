# ==============================================================================
# File: iam.tf
# Tier: Zero-Trust Identity, Session Manager & Instance Profile
# Description: IAM role + instance profile for the WordPress servers. Replaces
#              SSH with SSM Session Manager, allows the CloudWatch Agent, and
#              grants least-privilege access to the media bucket, the DB
#              password parameter and the app release bucket. No access keys.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. EC2 Assume Role Trust Policy
# ------------------------------------------------------------------------------
# Servers get short-lived credentials from the metadata service (IMDSv2),
# never static access keys.
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
# 2. SSM Session Manager (replaces SSH; port 22 stays closed)
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ------------------------------------------------------------------------------
# 3. CloudWatch Agent (RAM / disk metrics and logs, once the agent is installed)
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ------------------------------------------------------------------------------
# 4. Least-privilege S3 media access (WP Offload Media)
# ------------------------------------------------------------------------------
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
# 5. Runtime configuration: DB password (SSM) + app releases (S3), read-only
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "runtime_config" {
  name        = "${var.project_name}-runtime-config-policy"
  description = "Read-only access to the DB password parameter and app release bundles"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadProjectParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter/${var.project_name}/*"
      },
      {
        Sid      = "ReadAppReleases"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/releases/*"
      },
      {
        Sid      = "ListAppReleases"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.artifacts.arn
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-runtime-config-policy"
  }
}

resource "aws_iam_role_policy_attachment" "runtime_config" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.runtime_config.arn
}

# ------------------------------------------------------------------------------
# 6. Instance Profile (the container that attaches the role to EC2)
# ------------------------------------------------------------------------------
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2.name

  tags = {
    Name = "${var.project_name}-ec2-instance-profile"
  }
}
