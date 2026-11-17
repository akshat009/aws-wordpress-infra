# ==============================================================================
# File: compute-alb.tf
# Tier: Step 6 - Compute Tier (Standalone EC2 vs Application Load Balancer & ASG)
# Description: Demonstrates the contrast between an Enterprise Multi-AZ ALB + ASG
#              architecture and a Standalone Single-Server EC2 architecture.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Canonical Ubuntu 24.04 LTS Dynamic AMI Lookup
# ------------------------------------------------------------------------------
# Eliminates hardcoded AMI IDs (which vary by region and become deprecated monthly).
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical official owner ID

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
# 2. Standalone Single-Server Compute (Non-ALB, Non-ASG Setup)
# ------------------------------------------------------------------------------
# 💡 STANDALONE / BUDGET MODE:
# Single EC2 instance deployed in public subnet with an Elastic IP (EIP).
# Connects to local MySQL on localhost (RDS commented out).
resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data_replace_on_change = true

  user_data = base64encode(<<-EOF
#!/bin/bash
export DB_NAME="${var.db_name}"
export DB_USER="${var.db_username}"
export DB_PASS="${var.db_password}"
# 🏢 PROFESSIONAL PRODUCTION: export DB_HOST="${var.db_name}.rds.amazonaws.com"
# 💡 STANDALONE MODE: Local MySQL on same EC2
export DB_HOST="localhost"
export DOMAIN_NAME="${var.domain_name}"

${file("${path.module}/install.sh")}
EOF
  )

  tags = {
    Name = "${var.project_name}-standalone-web"
  }
}

# Static Elastic IP attached to the standalone web server
resource "aws_eip" "web" {
  instance = aws_instance.web.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-web-eip"
  }
}

# ==============================================================================
# 🏢 PROFESSIONAL PRODUCTION SETUP (ALB, TARGET GROUP, ASG & LAUNCH TEMPLATE):
# ==============================================================================
# In an enterprise production architecture:
# 1. We NEVER run a single snowflake EC2 instance with an Elastic IP (Single Point of Failure).
# 2. An Application Load Balancer distributes incoming traffic across multiple Availability Zones.
# 3. An Auto Scaling Group automatically heals failed instances and scales with traffic demand.
# 4. Instances are 100% stateless workers that connect to a decoupled Amazon RDS MySQL.
#
# Below, these resources are COMMENTED OUT for standalone single-instance mode:
# ==============================================================================

# ------------------------------------------------------------------------------
# ALB Target Group [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_lb_target_group" "web" {
#   name        = "${var.project_name}-web-tg"
#   port        = 80
#   protocol    = "HTTP"
#   vpc_id      = aws_vpc.main.id
#   target_type = "instance"
#
#   health_check {
#     enabled             = true
#     path                = "/health.html"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     matcher             = "200"
#     interval            = 15
#     timeout             = 5
#     healthy_threshold   = 2
#     unhealthy_threshold = 3
#   }
#
#   tags = {
#     Name = "${var.project_name}-web-tg"
#   }
# }

# ------------------------------------------------------------------------------
# Application Load Balancer [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_lb" "main" {
#   name               = "${var.project_name}-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.alb.id]
#   subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
#
#   enable_deletion_protection = false
#
#   tags = {
#     Name = "${var.project_name}-alb"
#   }
# }

# ------------------------------------------------------------------------------
# ALB HTTP:80 Listener (Auto-Redirect to HTTPS:443) [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_lb_listener" "http" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 80
#   protocol          = "HTTP"
#
#   default_action {
#     type = "redirect"
#
#     redirect {
#       port        = "443"
#       protocol    = "HTTPS"
#       status_code = "HTTP_301"
#     }
#   }
# }

# ------------------------------------------------------------------------------
# EC2 Launch Template [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_launch_template" "web" {
#   name_prefix   = "${var.project_name}-lt-"
#   image_id      = data.aws_ami.ubuntu.id
#   instance_type = var.instance_type
#
#   iam_instance_profile {
#     name = aws_iam_instance_profile.ec2.name
#   }
#
#   network_interfaces {
#     associate_public_ip_address = true
#     security_groups             = [aws_security_group.web.id]
#   }
#
#   user_data = base64encode(<<-EOF
# #!/bin/bash
# export DB_NAME="${var.db_name}"
# export DB_USER="${var.db_username}"
# export DB_PASS="${var.db_password}"
# export DB_HOST="${aws_db_instance.wordpress.address}"
# export DOMAIN_NAME="${var.domain_name}"
#
# ${file("${path.module}/install.sh")}
# EOF
#   )
#
#   tag_specifications {
#     resource_type = "instance"
#     tags = {
#       Name = "${var.project_name}-web-server"
#     }
#   }
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }

# ------------------------------------------------------------------------------
# Multi-AZ Auto Scaling Group [COMMENTED OUT FOR STANDALONE]
# ------------------------------------------------------------------------------
# resource "aws_autoscaling_group" "web" {
#   name_prefix               = "${var.project_name}-asg-"
#   vpc_zone_identifier       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
#   target_group_arns         = [aws_lb_target_group.web.arn]
#   health_check_type         = "ELB"
#   health_check_grace_period = 300
#
#   min_size         = var.asg_min_size
#   desired_capacity = var.asg_desired_capacity
#   max_size         = var.asg_max_size
#
#   launch_template {
#     id      = aws_launch_template.web.id
#     version = "$Latest"
#   }
#
#   tag {
#     key                 = "Name"
#     value               = "${var.project_name}-web-asg"
#     propagate_at_launch = true
#   }
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }
