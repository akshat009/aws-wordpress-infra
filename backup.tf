# ==============================================================================
# File: backup.tf
# Tier: Disaster Recovery
# Description: AWS Backup plan that snapshots every resource tagged
#              Backup = "daily" (the standalone server and RDS), kept 7 days.
#
# Off by default to keep the $0 promise. Turn on with enable_backups = true
# (snapshot storage is usually under $1/month for this stack). Strongly
# recommended in standalone mode, where the database lives on the server disk.
# ==============================================================================

resource "aws_backup_vault" "main" {
  count = var.enable_backups ? 1 : 0

  name = "${var.project_name}-backup-vault"

  tags = {
    Name = "${var.project_name}-backup-vault"
  }
}

resource "aws_backup_plan" "daily" {
  count = var.enable_backups ? 1 : 0

  name = "${var.project_name}-daily-backups"

  rule {
    rule_name         = "daily-keep-7-days"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = var.backup_schedule # UTC

    lifecycle {
      delete_after = 7
    }
  }

  tags = {
    Name = "${var.project_name}-daily-backups"
  }
}

# Role AWS Backup uses to create and restore snapshots
resource "aws_iam_role" "backup" {
  count = var.enable_backups ? 1 : 0

  name = "${var.project_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "backup.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  count = var.enable_backups ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  count = var.enable_backups ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Everything tagged Backup = "daily" is included automatically
resource "aws_backup_selection" "tagged" {
  count = var.enable_backups ? 1 : 0

  name         = "${var.project_name}-tagged-daily"
  plan_id      = aws_backup_plan.daily[0].id
  iam_role_arn = aws_iam_role.backup[0].arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "daily"
  }
}
