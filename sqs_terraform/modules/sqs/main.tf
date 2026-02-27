# --- DLQ (create only if var.create_queue = true) ---
resource "aws_sqs_queue" "dlq" {
  count = var.create_queue ? 1 : 0
  name  = "${var.queue_name}-dlq"

  kms_master_key_id = "alias/aws/sqs"

  message_retention_seconds = 1209600
}

# Look up existing DLQ if not creating
data "aws_sqs_queue" "dlq" {
  count = var.create_queue ? 0 : 1
  name  = "${var.queue_name}-dlq"
}

locals {
  dlq_arn = var.create_queue ? aws_sqs_queue.dlq[0].arn : data.aws_sqs_queue.dlq[0].arn
  dlq_url = var.create_queue ? aws_sqs_queue.dlq[0].url : data.aws_sqs_queue.dlq[0].url
}

# --- Main Queue (create only if var.create_queue = true) ---
resource "aws_sqs_queue" "this" {
  count = var.create_queue ? 1 : 0
  name  = var.queue_name

  kms_master_key_id = "alias/aws/sqs"

  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = local.dlq_arn
    maxReceiveCount     = 3
  })
}

# Look up existing main queue if not creating
data "aws_sqs_queue" "this" {
  count = var.create_queue ? 0 : 1
  name  = var.queue_name
}
