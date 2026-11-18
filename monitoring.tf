# ==============================================================================
# File: monitoring.tf
# Tier: Observability & Alerting
# Description: One SNS topic for every alert (alarms + budget), an optional
#              email subscription, and CloudWatch alarms that follow
#              architecture_mode automatically.
#
# Cost: stays inside the CloudWatch free tier (10 alarms) in every mode.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Alert topic + email subscription
# ------------------------------------------------------------------------------
# The topic was first created by hand in the console and adopted into Terraform
# with an import block (PR #18); the block was removed once the import was applied.

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name = "${var.project_name}-alerts"
  }
}

# Lets CloudWatch alarms and AWS Budgets publish to the topic.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountOwnerFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action = [
          "SNS:Publish",
          "SNS:Subscribe",
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:ListSubscriptionsByTopic",
          "SNS:DeleteTopic"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "AllowBudgets"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      }
    ]
  })
}

# AWS sends a confirmation email first; alerts arrive only after you click it.
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ------------------------------------------------------------------------------
# 2. Standalone server alarms (standalone + migrating)
# ------------------------------------------------------------------------------
# Hardware/host failure: AWS automatically recovers the instance onto healthy
# hardware (same instance ID, Elastic IP and disk) and emails you.
resource "aws_cloudwatch_metric_alarm" "standalone_system_check" {
  count = local.run_standalone && var.enable_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-standalone-system-check-failed"
  alarm_description   = "AWS host problem on the standalone server; auto-recovery triggered"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions          = { InstanceId = aws_instance.web[0].id }
  alarm_actions = [
    "arn:aws:automate:${var.aws_region}:ec2:recover",
    aws_sns_topic.alerts.arn
  ]
  ok_actions = [aws_sns_topic.alerts.arn]
}

# OS-level failure (kernel panic, out of memory, broken networking): reboot.
resource "aws_cloudwatch_metric_alarm" "standalone_instance_check" {
  count = local.run_standalone && var.enable_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-standalone-instance-check-failed"
  alarm_description   = "Standalone server OS is unresponsive; automatic reboot triggered"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions          = { InstanceId = aws_instance.web[0].id }
  alarm_actions = [
    "arn:aws:automate:${var.aws_region}:ec2:reboot",
    aws_sns_topic.alerts.arn
  ]
  ok_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "standalone_cpu_high" {
  count = local.run_standalone && var.enable_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-standalone-cpu-high"
  alarm_description   = "Standalone server CPU above 80% for 15 minutes (t3 burst credits draining)"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { InstanceId = aws_instance.web[0].id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# ------------------------------------------------------------------------------
# 3. Load balancer alarms (enterprise)
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = local.run_alb && var.enable_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-alb-unhealthy-hosts"
  alarm_description   = "One or more web servers are failing the /health.html check"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = aws_lb.main[0].arn_suffix
    TargetGroup  = aws_lb_target_group.web[0].arn_suffix
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count = local.run_alb && var.enable_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-alb-target-5xx"
  alarm_description   = "WordPress returned more than 10 server errors (5xx) in 5 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = aws_lb.main[0].arn_suffix }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# ------------------------------------------------------------------------------
# 4. Database alarms (migrating + enterprise)
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count = local.run_rds && var.enable_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-rds-cpu-high"
  alarm_description   = "RDS CPU above 80% for 15 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.wordpress[0].identifier }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  count = local.run_rds && var.enable_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-rds-free-storage-low"
  alarm_description   = "RDS free storage below 2 GB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648 # 2 GB in bytes
  comparison_operator = "LessThanThreshold"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.wordpress[0].identifier }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
