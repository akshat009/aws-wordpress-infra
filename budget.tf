# ==============================================================================
# File: budget.tf
# Tier: FinOps / Cost Control
# Description: Monthly AWS budget that alerts (via the SNS topic in
#              monitoring.tf) before a surprise bill arrives.
#
# Cost: the first two budgets in an account are free. This file manages exactly
#       two: the monthly limit below and the zero-spend alarm.
# ==============================================================================

resource "aws_budgets_budget" "monthly" {
  count = var.enable_budget ? 1 : 0

  name         = "${var.project_name}-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alert 1: actual spend has passed 80% of the limit
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  # Alert 2: AWS forecasts the month will end above the limit
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.alerts]
}

# The budget had no count before; keep the existing budget (same object, new address)
moved {
  from = aws_budgets_budget.monthly
  to   = aws_budgets_budget.monthly[0]
}

# ------------------------------------------------------------------------------
# Zero-spend budget: alerts as soon as ANY money is spent (a $0 / Free Tier setup
# should cost nothing). Created in the console from the "Zero spend" template
# before this project used Terraform; adopted with the import block below.
# Alerts go through the same SNS topic as everything else.
# ------------------------------------------------------------------------------
resource "aws_budgets_budget" "zero_spend" {
  count = var.enable_budget ? 1 : 0

  name         = "My Zero-Spend Budget" # the console name; renaming would recreate it
  budget_type  = "COST"
  limit_amount = "1.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 0.01
    threshold_type            = "ABSOLUTE_VALUE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.alerts]
}

# Adopt the existing console budget instead of creating a duplicate.
# for_each: only import when the budget is switched on (needs Terraform >= 1.7).
# Remove this block in a follow-up PR once the apply has run.
import {
  for_each = var.enable_budget ? toset(["zero_spend"]) : toset([])
  to       = aws_budgets_budget.zero_spend[0]
  id       = "${local.account_id}:My Zero-Spend Budget"
}
