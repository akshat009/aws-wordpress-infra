# Offline tests for the architecture_mode switch. Uses mocked AWS (no account,
# no cost). Run: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_ami" {
    defaults = { id = "ami-0123456789abcdef0", root_device_name = "/dev/sda1" }
  }
  mock_resource "aws_eip" {
    defaults = { public_ip = "16.4.164.224" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-south-1:123456789012:loadbalancer/app/wp-lab-alb/abc", dns_name = "wp-lab-alb-123.ap-south-1.elb.amazonaws.com", arn_suffix = "app/wp-lab-alb/abc" }
  }
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn                       = "arn:aws:acm:ap-south-1:123456789012:certificate/abc"
      domain_validation_options = [{ domain_name = "lab.asaxenadev.com", resource_record_name = "_x.lab.asaxenadev.com.", resource_record_type = "CNAME", resource_record_value = "_y.acm-validations.aws." }]
    }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:ap-south-1:123456789012:wp-lab-alerts" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/wp-lab-mock" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/wp-lab-mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::wp-lab-mock", id = "wp-lab-mock" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-south-1:123456789012:targetgroup/wp-lab-web-tg/abc", arn_suffix = "targetgroup/wp-lab-web-tg/abc" }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = { arn = "arn:aws:cloudfront::123456789012:distribution/ABC" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
}
mock_provider "random" {}

# monitoring.tf imports the pre-existing SNS topic; mock providers can't import,
# so the test supplies the imported topic's values directly.
override_resource {
  target = aws_sns_topic.alerts
  values = {
    arn = "arn:aws:sns:ap-south-1:123456789012:wp-lab-alerts"
  }
}

run "standalone" {
  command = apply
  variables { architecture_mode = "standalone" }
  assert {
    condition     = length(aws_instance.web) == 1 && length(aws_eip.web) == 1
    error_message = "standalone server missing"
  }
  assert {
    condition     = length(aws_db_instance.wordpress) == 0 && length(aws_lb.main) == 0 && length(aws_autoscaling_group.web) == 0 && length(aws_acm_certificate.cert) == 0
    error_message = "enterprise resources should not exist"
  }
  assert {
    condition     = length(aws_security_group.web.ingress) == 2 && alltrue([for r in aws_security_group.web.ingress : contains(r.cidr_blocks, "0.0.0.0/0")])
    error_message = "web-sg should allow 80/443 from internet"
  }
  assert {
    condition     = output.app_endpoint == "16.4.164.224" && output.rds_address == null && output.alb_dns_name == null
    error_message = "outputs wrong in standalone"
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.standalone_system_check) == 1 && length(aws_cloudwatch_metric_alarm.alb_unhealthy_hosts) == 0 && length(aws_cloudwatch_metric_alarm.rds_cpu_high) == 0
    error_message = "alarms wrong in standalone"
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0 && length(aws_backup_plan.daily) == 0
    error_message = "email sub / backups should be off by default"
  }
  assert {
    condition     = !strcontains(aws_instance.web[0].user_data, "SecureLabPass")
    error_message = "password leaked into user data"
  }
}

run "migrating" {
  command = apply
  variables { architecture_mode = "migrating" }
  assert {
    condition     = length(aws_instance.web) == 1 && length(aws_db_instance.wordpress) == 1 && length(aws_acm_certificate.cert) == 1
    error_message = "migrating needs standalone + RDS + cert"
  }
  assert {
    condition     = length(aws_lb.main) == 0 && length(aws_acm_certificate_validation.cert) == 0 && length(aws_lb_listener.https) == 0
    error_message = "migrating must not create ALB or wait on validation"
  }
  assert {
    condition     = length(output.acm_dns_validation_records) == 1 && output.app_endpoint == "16.4.164.224"
    error_message = "migrating outputs wrong"
  }
  assert {
    condition     = aws_db_instance.wordpress[0].storage_encrypted && !aws_db_instance.wordpress[0].skip_final_snapshot && aws_db_instance.wordpress[0].engine_version == "8.4"
    error_message = "RDS hardening missing"
  }
}

run "enterprise" {
  command = apply
  variables {
    architecture_mode = "enterprise"
    alert_email       = "alerts@example.com"
    enable_backups    = true
  }
  assert {
    condition     = length(aws_instance.web) == 0 && length(aws_eip.web) == 0
    error_message = "standalone should be gone"
  }
  assert {
    condition     = length(aws_lb.main) == 1 && length(aws_autoscaling_group.web) == 1 && length(aws_autoscaling_policy.cpu) == 1 && length(aws_lb_listener.https) == 1 && length(aws_db_instance.wordpress) == 1
    error_message = "enterprise stack incomplete"
  }
  assert {
    condition     = length(aws_security_group.web.ingress) == 1 && alltrue([for r in aws_security_group.web.ingress : length(coalesce(r.cidr_blocks, [])) == 0 && length(r.security_groups) == 1 && r.from_port == 80])
    error_message = "web-sg should only allow 80 from ALB"
  }
  assert {
    condition     = output.app_endpoint == "wp-lab-alb-123.ap-south-1.elb.amazonaws.com" && output.wordpress_public_ip == null
    error_message = "enterprise outputs wrong"
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1 && length(aws_backup_selection.tagged) == 1
    error_message = "email sub / backups should be on"
  }
  assert {
    condition     = strcontains(output.dns_instructions, "CNAME  lab  ->")
    error_message = "dns instructions wrong"
  }
}

run "invalid_mode_rejected" {
  command = plan
  variables { architecture_mode = "bogus" }
  expect_failures = [var.architecture_mode]
}
