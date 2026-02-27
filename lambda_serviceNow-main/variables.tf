
variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile"
  default     = "default"
}

variable "project" {
  type    = string
  default = "evtbridge-lambda-sqs"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional default tags"
}

variable "lambda_runtime" {
  type    = string
  default = "python3.12"
}

variable "lambda_timeout" {
  type    = number
  default = 30
}

variable "lambda_memory_mb" {
  type    = number
  default = 256
}

variable "cloudwatch_log_retention_days" {
  type    = number
  default = 14
}

variable "sqs_message_retention_seconds" {
  type    = number
  default = 345600 # 4 days
}

variable "sqs_visibility_timeout_seconds" {
  type    = number
  default = 60
}

# EventBridge rule configuration
variable "create_eventbridge_rule" {
  type        = bool
  description = "Whether to create an EventBridge rule in this module (set false if using external EventBridge)"
  default     = false
}

variable "event_pattern" {
  description = "EventBridge event pattern for triggering this Lambda"
  type        = any
  default = {
    source      = ["custom.myapp"]
    detail-type = ["lambda-trigger"]
  }
}

# SQS mapping controls
variable "sqs_batch_size" {
  type    = number
  default = 5
}

variable "sqs_max_batching_window" {
  type    = number
  default = 1
}

# Optional: use existing SQS queue(s) instead of creating new ones
variable "sqs_existing_queue_name" {
  type        = string
  description = "Name of an existing SQS queue to use (leave empty to create a new queue)"
  default     = ""
}

variable "sqs_existing_dlq_name" {
  type        = string
  description = "Name of an existing SQS dead-letter queue to use (leave empty to create a new DLQ)"
  default     = ""
}

# Direct queue references (used when queues are created externally)
variable "sqs_queue_url" {
  type        = string
  description = "URL of SQS queue (provide this instead of sqs_existing_queue_name)"
  default     = ""
}

variable "sqs_queue_arn" {
  type        = string
  description = "ARN of SQS queue (provide this instead of sqs_existing_queue_name)"
  default     = ""
}

variable "sqs_dlq_arn" {
  type        = string
  description = "ARN of SQS dead-letter queue"
  default     = ""
}

# ServiceNow OAuth configuration via Secrets Manager
variable "servicenow_secret_name" {
  type        = string
  description = "Name of the AWS Secrets Manager secret containing ServiceNow OAuth credentials"
  default     = "servicenow/oauth_token"
  validation {
    condition     = length(var.servicenow_secret_name) > 0
    error_message = "servicenow_secret_name must be set."
  }
}

variable "snow_instance" {
  type        = string
  description = "ServiceNow instance (e.g., dev12345)"
  default     = "dev192366"
  validation {
    condition     = length(var.snow_instance) > 0
    error_message = "snow_instance must be set (e.g., dev12345)."
  }
}

variable "snow_table" {
  type        = string
  default     = "incident"
  description = "ServiceNow table to create record in (default: incident)"
}

# ============================================================================
# Lambda Resource Creation Control (Idempotent Pattern)
# ============================================================================
# whether this module should attempt to create the function or simply look up an
# existing one; similar to the idempotent variables used for KMS/iam/log group
variable "create_lambda" {
  type        = bool
  description = <<-EOT
Create a new Lambda function, or reference an existing one (idempotent: false = use existing).
If the function already exists in AWS the module will automatically use the existing resource and skip creation.
EOT
  default     = true
}

variable "existing_lambda_function_name" {
  type        = string
  description = "Name of an existing Lambda function to reference when create_lambda is false or when a pre‑existing function is detected."
  default     = ""
  validation {
    condition     = !(var.create_lambda == false && var.existing_lambda_function_name == "")
    error_message = "existing_lambda_function_name must be provided when create_lambda is false."
  }
}

variable "create_lambda_kms" {
  type        = bool
  description = "Create new KMS key for Lambda env vars, or use existing one (idempotent: false=use existing, true=create if not exists)"
  default     = true
}

variable "create_lambda_iam" {
  type        = bool
  description = "Create new IAM role for Lambda, or use existing one (idempotent: false=use existing, true=create if not exists)"
  default     = true
}

variable "create_lambda_loggroup" {
  type        = bool
  description = "Create new CloudWatch log group for Lambda, or use existing one (idempotent: false=use existing, true=create if not exists)"
  default     = true
}
