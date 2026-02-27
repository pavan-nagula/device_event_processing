output "queue_name" {
  value       = module.events_queue.queue_name
  description = "SQS queue name"
}

output "queue_url" {
  value       = module.events_queue.queue_url
  description = "SQS queue URL"
}

output "queue_arn" {
  value       = module.events_queue.queue_arn
  description = "SQS queue ARN"
}

output "dlq_arn" {
  value       = module.events_queue.dlq_arn
  description = "SQS Dead Letter Queue ARN"
}

output "queue_alerts_sns_arn" {
  value       = try(aws_sns_topic.queue_alerts[0].arn, null)
  description = "SNS topic ARN for queue alerts (if created)"
}

output "queue_depth_alarm_arn" {
  value       = try(aws_cloudwatch_metric_alarm.sqs_queue_depth[0].arn, null)
  description = "CloudWatch alarm ARN for queue depth (if created)"
}
