# ==============================================================================
# File: locals.tf
# Tier: Derived Settings
# Description: Turns architecture_mode (a preset) + the optional enable_* switches
#              into the on/off flags every other file uses as
#              `count = local.<flag> ? 1 : 0`.
# ==============================================================================

locals {
  # ----------------------------------------------------------------------------
  # Presets: what each architecture_mode turns on
  # ----------------------------------------------------------------------------
  #                standalone   migrating   enterprise
  # rds                no          yes          yes
  # alb                no          no           yes
  # asg (fleet)        no          no           yes
  presets = {
    standalone = { rds = false, alb = false, asg = false }
    migrating  = { rds = true, alb = false, asg = false }
    enterprise = { rds = true, alb = true, asg = true }
  }
  preset = local.presets[var.architecture_mode]

  # ----------------------------------------------------------------------------
  # Individual switches override the preset (null = use the preset)
  # ----------------------------------------------------------------------------
  run_rds        = var.enable_rds != null ? var.enable_rds : local.preset.rds
  run_alb        = var.enable_alb != null ? var.enable_alb : local.preset.alb
  run_fleet      = var.enable_asg != null ? var.enable_asg : local.preset.asg
  run_standalone = !local.run_fleet # the single server exists unless the fleet replaces it

  # The ACM certificate exists whenever there is a load balancer. In
  # "migrating" it is requested one stage early, so its DNS validation record
  # can be added before the load balancer needs it (avoids a validation hang).
  request_certificate = local.run_alb || var.architecture_mode == "migrating"

  account_id = data.aws_caller_identity.current.account_id

  # SSM Parameter Store path for the database password (see secrets.tf)
  db_password_param = "/${var.project_name}/db/password"

  # Name tag of the standalone server; workflows find it by this exact value
  standalone_name = "${var.project_name}-standalone-web"
}

# ------------------------------------------------------------------------------
# Rule check: block combinations that can't work (fails at plan time)
# ------------------------------------------------------------------------------
# An Auto Scaling fleet runs 2-4 servers. Each would otherwise have its own local
# database (different posts/users per server), so the fleet needs RDS, and it
# needs the load balancer to spread traffic.
resource "terraform_data" "feature_rules" {
  input = {
    rds   = local.run_rds
    alb   = local.run_alb
    fleet = local.run_fleet
  }

  lifecycle {
    precondition {
      condition     = !local.run_fleet || (local.run_alb && local.run_rds)
      error_message = "enable_asg (the Auto Scaling fleet) needs enable_alb = true and enable_rds = true: servers in a fleet must share one database (RDS) behind a load balancer."
    }
  }
}
