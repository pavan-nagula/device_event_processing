variable "queue_name" {
  type        = string
  description = "Name of the SQS queue"
  default     = "events-queue"
}

variable "create_sns_alerts" {
  type        = bool
  description = "Create SNS topic for alerts"
  default     = false
}

variable "alert_email" {
  type        = string
  description = "Email address for SNS notifications"
  default     = "nagualapavan@gmail.com"
}

variable "create_cloudwatch_alarms" {
  type        = bool
  description = "Create CloudWatch alarms for queue monitoring"
  default     = false
}

variable "queue_depth_threshold" {
  type        = number
  description = "Threshold for queue depth alarm"
  default     = 90
}

variable "tags" {
  type        = map(string)
  description = "Tags for all resources"
  default     = {}
}
