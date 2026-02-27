variable "queue_name" {
  type        = string
  description = "Name of the SQS queue"
}

variable "create_queue" {
  type        = bool
  description = "Create new SQS queue and DLQ, or use existing ones (idempotent: false=use existing, true=create if not exists)"
  default     = true
}
