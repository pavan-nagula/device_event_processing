output "queue_url" {
  value = var.create_queue ? aws_sqs_queue.this[0].url : data.aws_sqs_queue.this[0].url
}

output "queue_arn" {
  value = var.create_queue ? aws_sqs_queue.this[0].arn : data.aws_sqs_queue.this[0].arn
}

output "queue_name" {
  value = var.create_queue ? aws_sqs_queue.this[0].name : data.aws_sqs_queue.this[0].name
}

output "dlq_arn" {
  value = local.dlq_arn
}

output "dlq_name" {
  value = var.create_queue ? aws_sqs_queue.dlq[0].name : data.aws_sqs_queue.dlq[0].name
}
