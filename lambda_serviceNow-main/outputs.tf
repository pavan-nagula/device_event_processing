output "lambda_function_name" {
  value = local.lambda_function_name
}

output "lambda_function_arn" {
  value = local.lambda_function_arn
}

output "sqs_queue_url" {
  value = var.sqs_queue_url
}

output "sqs_queue_arn" {
  value = var.sqs_queue_arn
}

output "sqs_dlq_arn" {
  value = var.sqs_dlq_arn
}

output "eventbridge_rule_arn" {
  value = try(aws_cloudwatch_event_rule.rule[0].arn, null)
}

output "eventbridge_rule_name" {
  value = try(aws_cloudwatch_event_rule.rule[0].name, null)
}

output "debug_lambda_exists" {
  value = local.lambda_exists
}

output "debug_effective_create_lambda" {
  value = local.effective_create_lambda
}
