# ==============================================================================
# File: locals.tf
# Tier: Derived Settings
# Description: Turns the single architecture_mode switch into on/off flags that
#              every other file uses as `count = local.<flag> ? 1 : 0`.
# ==============================================================================

locals {
  # ----------------------------------------------------------------------------
  # Which building blocks exist in each mode
  # ----------------------------------------------------------------------------
  #                     standalone   migrating   enterprise
  # run_standalone          yes         yes          no      (EC2 + EIP + local MySQL)
  # run_rds                 no          yes          yes     (RDS + ACM certificate)
  # run_fleet               no          no           yes     (ALB + ASG + HTTPS listener)
  run_standalone = contains(["standalone", "migrating"], var.architecture_mode)
  run_rds        = contains(["migrating", "enterprise"], var.architecture_mode)
  run_fleet      = var.architecture_mode == "enterprise"

  # The ACM certificate is requested one stage early (in "migrating") so its DNS
  # validation record can be added to Hostinger before the ALB needs it. This
  # avoids the apply hanging on validation (see notes/15).
  request_certificate = local.run_rds

  account_id = data.aws_caller_identity.current.account_id

  # SSM Parameter Store path for the database password (see secrets.tf)
  db_password_param = "/${var.project_name}/db/password"

  # Name tag of the standalone server; workflows find it by this exact value
  standalone_name = "${var.project_name}-standalone-web"
}
