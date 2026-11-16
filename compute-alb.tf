# ==============================================================================
# File: compute-alb.tf
# Tier: Step 6 - Application Load Balancer & Auto Scaling Compute Fleet
# Description: Provisions the Internet-facing Application Load Balancer (ALB),
#              Target Group with health checks, Launch Template configured with
#              IAM Instance Profile, and a Multi-AZ Auto Scaling Group.
# ==============================================================================
#
# ==============================================================================
# 💡 ARCHITECTURE GUIDE: WHAT IF YOU DO NOT WANT TO USE A LOAD BALANCER (ALB)?
# (Cost Savings / Single Instance / Non-ALB Setup Guide)
# ==============================================================================
# If you want to run WordPress on a single standalone EC2 instance without an ALB
# (e.g. to save ~$16-20 USD/month on AWS ALB hourly billing), you need to make
# the following changes across 5 areas of your Terraform codebase:
#
# 1. IN THIS FILE (compute-alb.tf):
#    - Comment out or delete:
#        * aws_lb_target_group.web (Lines 70-96)
#        * aws_lb.main (Lines 98-115)
#        * aws_lb_listener.http (Lines 117-135)
#        * aws_autoscaling_group.web (Lines 185-210)
#    - Replace with a single standalone EC2 instance + Elastic IP (EIP):
#        resource "aws_instance" "web" {
#          ami                    = data.aws_ami.ubuntu.id
#          instance_type          = var.instance_type
#          subnet_id              = aws_subnet.public_1.id
#          vpc_security_group_ids = [aws_security_group.web.id]
#          iam_instance_profile   = aws_iam_instance_profile.ec2.name
#          user_data              = aws_launch_template.web.user_data # or inline base64 user_data
#          tags                   = { Name = "${var.project_name}-standalone-web" }
#        }
#        resource "aws_eip" "web" {
#          instance = aws_instance.web.id
#          domain   = "vpc"
#        }
#
# 2. IN security-groups.tf:
#    - aws_security_group.alb is NOT needed (comment out).
#    - In aws_security_group.web:
#        * Web server will now face the public internet directly.
#        * Change ingress port 80 & port 443 from 'security_groups = [aws_security_group.alb.id]'
#          to 'cidr_blocks = ["0.0.0.0/0"]'.
#
# 3. IN ssl.tf:
#    - AWS ACM public certificates CANNOT be attached directly to an EC2 instance!
#      (ACM certificates can only be attached to ALB, NLB, CloudFront, or API Gateway).
#    - Comment out aws_lb_listener.https.
#    - To get free SSL without an ALB, install Certbot (Let's Encrypt) inside EC2
#      via install.sh: 'apt install certbot python3-certbot-nginx -y'
#
# 4. IN outputs.tf:
#    - Remove/comment out 'alb_dns_name' and 'target_group_arn'.
#    - Add output for the Elastic IP:
#        output "wordpress_public_ip" {
#          value = aws_eip.web.public_ip
#        }
#
# 5. IN DNS (Hostinger / Registrar):
#    - Change the DNS record from a 'CNAME' (pointing to the ALB DNS name)
#      to an 'A' Record (pointing directly to the Elastic IP of the EC2 instance).
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
# 4. ALB HTTP:80 Ingress Listener (Auto-Redirect to HTTPS:443)
# ------------------------------------------------------------------------------
# Automatically redirects all plain HTTP port 80 requests to encrypted HTTPS:443.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
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
export DOMAIN_NAME="${var.domain_name}"

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
