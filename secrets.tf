# ==============================================================================
# File: secrets.tf
# Tier: Secrets Management
# Description: Generates the database password and stores it in AWS Systems
#              Manager Parameter Store as an encrypted SecureString.
#
# Why: passwords must never be committed to Git or passed in EC2 user data
# (anyone with ec2:DescribeInstanceAttribute can read user data). Servers and the
# migration script read the password at runtime with their IAM role instead.
#
# Cost: Parameter Store standard parameters are free (Secrets Manager would be
# ~$0.40/secret/month, which is the usual choice when automatic rotation is needed).
# ==============================================================================

resource "random_password" "db" {
  length  = 24
  special = true

  # Only characters that are safe in MySQL, RDS, PHP strings and sed replacements
  # (no quotes, slashes, backslashes, '@', '&' or '|').
  override_special = "-_.+=!%^*"
}

resource "aws_ssm_parameter" "db_password" {
  name        = local.db_password_param
  description = "WordPress database password (read by EC2 at boot and by scripts/migrate-db.sh)"
  type        = "SecureString" # Encrypted with the AWS managed KMS key aws/ssm
  value       = random_password.db.result

  tags = {
    Name = "${var.project_name}-db-password"
  }
}
