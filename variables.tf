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

variable "project_name" {
  type        = string
  description = "Project name for resource naming"
  default     = "device-events"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags for all resources"
}

# ============================================================================
# Lambda Configuration
# ============================================================================
variable "lambda_runtime" {
  type        = string
  description = "Lambda runtime"
  default     = "python3.12"
}

variable "lambda_timeout" {
  type        = number
  description = "Lambda timeout in seconds"
  default     = 30
}

variable "lambda_memory_mb" {
  type        = number
  description = "Lambda memory allocation in MB"
  default     = 256
}

variable "cloudwatch_log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 14
}

# ============================================================================
# SQS Configuration
# ============================================================================
variable "create_sqs" {
  type        = bool
  description = "Create new SQS queue and DLQ, or use existing ones (idempotent: false=use existing, true=create if not exists)"
  default     = true
}

variable "sqs_batch_size" {
  type        = number
  description = "SQS batch size for Lambda event source mapping"
  default     = 5
}

variable "sqs_max_batching_window" {
  type        = number
  description = "SQS max batching window in seconds"
  default     = 1
}

# ============================================================================
# EventBridge Configuration
# ============================================================================
variable "create_event_bus" {
  type        = bool
  description = "Create a new EventBridge bus or use existing one (idempotent: false=use existing, true=create if not exists)"
  default     = true
}

variable "event_bus_name" {
  type        = string
  description = "EventBridge bus name"
  default     = "device-events-bus"
}

variable "allow_org_id" {
  type        = string
  description = "Allow events from this AWS Organization ID"
  default     = null
}

variable "allow_account_ids" {
  type        = list(string)
  description = "Allow events from these AWS account IDs"
  default     = []
}

variable "create_archive" {
  type        = bool
  description = "Create EventBridge archive for replay"
  default     = true
}

variable "archive_name" {
  type        = string
  description = "EventBridge archive name"
  default     = "device-events-archive"
}

variable "event_sources" {
  type        = list(string)
  description = "Event sources to match in EventBridge rules"
  default     = ["device.iot", "device.sensor"]
}

variable "event_detail_types" {
  type        = list(string)
  description = "Event detail types to match in EventBridge rules"
  default     = ["device-reading", "device-alert", "device-status"]
}

variable "event_pattern" {
  type        = any
  description = "Event pattern for Lambda trigger"
  default = {
    source      = ["device.iot", "device.sensor"]
    detail-type = ["device-reading", "device-alert", "device-status"]
  }
}

variable "lambda_input_paths" {
  type        = map(string)
  description = "Lambda input transformer paths"
  default     = null
}

variable "lambda_input_template" {
  type        = string
  description = "Lambda input transformer template"
  default     = null
}

# ============================================================================
# Lambda Resource Creation Control (Idempotent Pattern)
# ============================================================================
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

variable "create_lambda" {
  type        = bool
  description = "Create a new Lambda function or reference an existing one (idempotent: false = use existing)"
  default     = true
}

variable "existing_lambda_function_name" {
  type        = string
  description = "Name of an existing Lambda function to reference when create_lambda is false"
  default     = ""
}

variable "create_lambda_loggroup" {
  type        = bool
  description = "Create new CloudWatch log group for Lambda, or use existing one (idempotent: false=use existing, true=create if not exists)"
  default     = true
}

variable "create_eventbridge_role" {
  type        = bool
  description = "Create new IAM role for EventBridge, or use existing one (idempotent: false=use existing, true=create if not exists)"
  default     = true
}

# ============================================================================
# ServiceNow Configuration
# ============================================================================
variable "snow_instance" {
  type        = string
  description = "ServiceNow instance URL"
  default     = "dev192366"
}

variable "servicenow_secret_name" {
  type        = string
  sensitive   = false
  description = "Name of AWS Secrets Manager secret containing ServiceNow OAuth credentials (client_id, client_secret)"
  default     = "servicenow/oauth_token"
}

variable "snow_table" {
  type        = string
  description = "ServiceNow table to create records in"
  default     = "incident"
}
