# ==============================================================================
# File: compute-alb.tf
# Tier: Compute (Standalone EC2  <->  Application Load Balancer + Auto Scaling)
# Description: Both architectures live here. architecture_mode (variables.tf)
#              decides which one exists, through the flags in locals.tf:
#                - local.run_standalone : single EC2 + Elastic IP
#                - local.run_fleet      : ALB + target group + launch template + ASG
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Canonical Ubuntu 24.04 LTS AMI lookup (no hard-coded AMI IDs)
# ------------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------------------
# 2. Boot configuration shared by both modes
# ------------------------------------------------------------------------------
# No secrets here: install.sh reads the DB password from SSM Parameter Store.
locals {
  boot_env = <<-EOT
    export DB_NAME="${var.db_name}"
    export DB_USER="${var.db_username}"
    export DB_PASSWORD_PARAM="${local.db_password_param}"
    export AWS_REGION="${var.aws_region}"
    export DOMAIN_NAME="${var.domain_name}"
    export ARTIFACT_BUCKET="${aws_s3_bucket.artifacts.id}"
  EOT
}

# ==============================================================================
# STANDALONE MODE (architecture_mode = "standalone" or "migrating")
# ==============================================================================
# One EC2 in a public subnet with an Elastic IP, running Nginx + PHP + local
# MySQL. Cheapest possible setup (~$0 on Free Tier) but a single point of failure.
resource "aws_instance" "web" {
  count = local.run_standalone ? 1 : 0

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data_replace_on_change = false

  # IMDSv2 only: blocks SSRF-style credential theft through the metadata service.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
${local.boot_env}
export DB_HOST="${local.run_rds ? one(aws_db_instance.wordpress[*].address) : "localhost"}"
export INSTALL_LOCAL_DB="true"

${file("${path.module}/install.sh")}
EOF
  )

  # This server holds the local database, so it must never be replaced by
  # accident. A new Ubuntu AMI release or an edit to install.sh would otherwise
  # force a replacement. It is only removed on purpose, by switching
  # architecture_mode to "enterprise" (after the data has been moved to RDS).
  #
  # Note: prevent_destroy was removed because it cannot be made conditional and
  # would block the planned mode switch. The safety net is now: ignore_changes
  # below + plan review/approval in the "production" environment of terraform.yml.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name   = local.standalone_name
    Backup = "daily" # Picked up by backup.tf when enable_backups = true
  }
}

# Static Elastic IP for the standalone server (the DNS "A" record points here)
resource "aws_eip" "web" {
  count = local.run_standalone ? 1 : 0

  instance = aws_instance.web[0].id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-web-eip"
  }
}

# The resources above used to have no count. These blocks tell Terraform the
# existing server and IP are the same objects, so nothing is recreated.
moved {
  from = aws_instance.web
  to   = aws_instance.web[0]
}

moved {
  from = aws_eip.web
  to   = aws_eip.web[0]
}

# ==============================================================================
# ENTERPRISE MODE (architecture_mode = "enterprise")
# ==============================================================================
# ALB spreads traffic across 2 AZs; the Auto Scaling Group replaces unhealthy
# servers and adds/removes servers with CPU load. Servers are stateless: data in
# RDS, media in S3, app code pulled from the artifacts bucket at boot.
#
# Cost trade-off kept on purpose: servers sit in PUBLIC subnets (locked down so
# only the ALB can reach port 80) instead of private subnets + NAT gateway,
# which would add ~$33-45/month per NAT.

# ------------------------------------------------------------------------------
# ALB Target Group (health checked on /health.html)
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "web" {
  count = local.run_alb ? 1 : 0

  name        = "${var.project_name}-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health.html"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-web-tg"
  }
}

# ------------------------------------------------------------------------------
# Application Load Balancer (internet-facing, 2 AZs)
# ------------------------------------------------------------------------------
resource "aws_lb" "main" {
  count = local.run_alb ? 1 : 0

  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  drop_invalid_header_fields = true  # Rejects malformed headers (request smuggling defence)
  enable_deletion_protection = false # Must stay false so a downgrade can remove the ALB

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# ------------------------------------------------------------------------------
# ALB HTTP:80 Listener (301 redirect to HTTPS:443)
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  count = local.run_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ------------------------------------------------------------------------------
# EC2 Launch Template (blueprint for every server in the fleet)
# ------------------------------------------------------------------------------
resource "aws_launch_template" "web" {
  count = local.run_fleet ? 1 : 0

  name_prefix            = "${var.project_name}-lt-"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  # Encrypted gp3 root disk
  block_device_mappings {
    device_name = data.aws_ami.ubuntu.root_device_name

    ebs {
      volume_size           = 10
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
${local.boot_env}
export DB_HOST="${try(aws_db_instance.wordpress[0].address, "")}"

${file("${path.module}/install.sh")}
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-web-server"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# Multi-AZ Auto Scaling Group
# ------------------------------------------------------------------------------
resource "aws_autoscaling_group" "web" {
  count = local.run_fleet ? 1 : 0

  name_prefix               = "${var.project_name}-asg-"
  vpc_zone_identifier       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  target_group_arns         = aws_lb_target_group.web[*].arn
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_capacity
  max_size         = var.asg_max_size

  launch_template {
    id      = aws_launch_template.web[0].id
    version = aws_launch_template.web[0].latest_version
  }

  # Any launch template change (new AMI, new install.sh) rolls the fleet
  # gradually instead of leaving old servers running forever.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    # The scaling policy changes desired_capacity at runtime; don't fight it.
    ignore_changes = [desired_capacity]
  }
}

# ------------------------------------------------------------------------------
# Target Tracking Scaling Policy (keep average CPU near var.asg_cpu_target)
# ------------------------------------------------------------------------------
resource "aws_autoscaling_policy" "cpu" {
  count = local.run_fleet ? 1 : 0

  name                   = "${var.project_name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web[0].name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.asg_cpu_target
  }
}

# ------------------------------------------------------------------------------
# Load balancer in front of the SINGLE server (enable_alb without the fleet)
# ------------------------------------------------------------------------------
resource "aws_lb_target_group_attachment" "standalone" {
  count = local.run_alb && local.run_standalone ? 1 : 0

  target_group_arn = aws_lb_target_group.web[0].arn
  target_id        = aws_instance.web[0].id
  port             = 80
}
