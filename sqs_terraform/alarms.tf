
resource "aws_cloudwatch_metric_alarm" "events_queue_depth" {
  alarm_name          = "events-queue-high-load"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 90
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    QueueName = module.events_queue.queue_name
  }

  alarm_actions = [aws_sns_topic.queue_alerts[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "sqs_oldest_message" {
  alarm_name          = "sqs-oldest-message-events-queue"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 120

  dimensions = {
    QueueName = module.events_queue.queue_name
  }

  alarm_actions = [aws_sns_topic.queue_alerts[0].arn]

}


