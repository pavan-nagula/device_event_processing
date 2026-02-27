# This module is now used in the root ../main.tf
# It creates an SQS queue with DLQ enabled
# 
# Note: This directory is kept for backward compatibility and direct testing
# In production, use the root ../main.tf which orchestrates all three modules

module "events_queue" {
  source = "./modules/sqs"

  queue_name = var.queue_name
}

# Check if SNS topic already exists
data "aws_sns_topic" "queue_alerts_existing" {
  count = var.create_sns_alerts ? 1 : 0
  name  = "${var.queue_name}-alerts"
}

# Optional: CloudWatch Alarm for queue depth monitoring
resource "aws_sns_topic" "queue_alerts" {
  count = var.create_sns_alerts ? (try(data.aws_sns_topic.queue_alerts_existing[0].id, null) == null ? 1 : 0) : 0
  name  = "${var.queue_name}-alerts"
  tags  = var.tags
}

# Get SNS topic ARN - use existing or newly created
locals {
  sns_topic_arn = var.create_sns_alerts ? (try(data.aws_sns_topic.queue_alerts_existing[0].arn, aws_sns_topic.queue_alerts[0].arn)) : null
}

# Check if email subscription already exists
data "aws_sns_topic_subscriptions" "email_existing" {
  count     = var.create_sns_alerts ? 1 : 0
  topic_arn = local.sns_topic_arn
}

resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.create_sns_alerts ? (length(data.aws_sns_topic_subscriptions.email_existing[0].subscriptions) > 0 ? 0 : 1) : 0
  topic_arn = local.sns_topic_arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Check if CloudWatch alarm already exists
data "aws_cloudwatch_metric_alarm" "sqs_queue_depth_existing" {
  count      = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name = "${var.queue_name}-high-depth"
}

# CloudWatch Alarm - Queue Depth (create only if doesn't exist)
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  count               = var.create_cloudwatch_alarms ? (try(data.aws_cloudwatch_metric_alarm.sqs_queue_depth_existing[0].arn, null) == null ? 1 : 0) : 0
  alarm_name          = "${var.queue_name}-high-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = var.queue_depth_threshold
  alarm_description   = "Alert when queue depth is high"
  dimensions = {
    QueueName = module.events_queue.queue_name
  }
  alarm_actions = var.create_sns_alerts ? [local.sns_topic_arn] : []
  tags          = var.tags
}

