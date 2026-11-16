# ==============================================================================
# File: compute-alb.tf
# Tier: Step 6 - Application Load Balancer & Auto Scaling Compute Fleet
# Description: Provisions the Internet-facing Application Load Balancer (ALB),
#              Target Group with health checks, Launch Template configured with
#              IAM Instance Profile, and a Multi-AZ Auto Scaling Group.
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
# 2. ALB Target Group (Health Monitoring & Routing)
# ------------------------------------------------------------------------------
# Monitors the operational health of EC2 instances. If an instance fails,
# the ALB automatically stops sending traffic to it and ASG launches a replacement.
resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health.html" # Dedicated ultra-fast health endpoint
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
# 3. Application Load Balancer (Public Ingress & SSL Termination)
# ------------------------------------------------------------------------------
# In Phase 9, we replaced single EC2 public IPs with an ALB.
# The ALB spans across TWO Public Subnets (ap-south-1a & ap-south-1b) for High Availability.
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false # Public-facing on the Internet
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  enable_deletion_protection = false # Convenient for lab teardown

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# ------------------------------------------------------------------------------
# 4. ALB HTTP:80 Ingress Listener
# ------------------------------------------------------------------------------
# Forwards incoming port 80 HTTP web requests to the Target Group fleet.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ------------------------------------------------------------------------------
# 5. EC2 Launch Template (Golden Configuration Blueprint)
# ------------------------------------------------------------------------------
# Encapsulates the compute instance blueprint: Ubuntu AMI, IAM Instance Profile,
# Chained Security Group, and Cloud-Init bootstrap script with RDS connection.
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
export DB_NAME="${var.db_name}"
export DB_USER="${var.db_username}"
export DB_PASS="${var.db_password}"
export DB_HOST="${aws_db_instance.wordpress.address}"

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
# 6. Multi-AZ Auto Scaling Group (ASG)
# ------------------------------------------------------------------------------
# Maintains our fleet of stateless WordPress instances across multiple availability zones.
# Automatically self-heals by replacing any instance marked unhealthy by the ALB.
resource "aws_autoscaling_group" "web" {
  name_prefix               = "${var.project_name}-asg-"
  vpc_zone_identifier       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300 # Allow 5 minutes for Ubuntu apt packages to install

  min_size         = var.asg_min_size         # 1 instance
  desired_capacity = var.asg_desired_capacity # 2 instances across 2 AZs
  max_size         = var.asg_max_size         # 4 instances during peak traffic

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
