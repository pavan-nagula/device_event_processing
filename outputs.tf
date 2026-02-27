# ============================================================================
# EventBridge Outputs
# ============================================================================
output "event_bus_name" {
  value       = module.eventbridge.event_bus_name
  description = "EventBridge bus name"
}

output "event_bus_arn" {
  value       = module.eventbridge.event_bus_arn
  description = "EventBridge bus ARN"
}

output "eventbridge_rule_arns" {
  value       = module.eventbridge.rule_arns
  description = "Map of EventBridge rule names to ARNs"
}

output "archive_arn" {
  value       = module.eventbridge.archive_arn
  description = "EventBridge archive ARN (for replay)"
}

# ============================================================================
# Lambda Outputs
# ============================================================================
output "lambda_function_name" {
  value       = module.lambda_servicenow.lambda_function_name
  description = "Lambda function name"
}

output "lambda_function_arn" {
  value       = module.lambda_servicenow.lambda_function_arn
  description = "Lambda function ARN"
}

output "module_lambda_exists" {
  value       = module.lambda_servicenow.debug_lambda_exists
  description = "Whether the external check detected an existing lambda"
}

output "module_effective_create_lambda" {
  value       = module.lambda_servicenow.debug_effective_create_lambda
  description = "Computed create flag inside the lambda_servicenow module"
}

# ============================================================================
# SQS Outputs
# ============================================================================
output "sqs_queue_name" {
  value       = "${var.project_name}-${var.environment}-events"
  description = "SQS queue name"
}

output "sqs_queue_url" {
  value       = local.sqs_queue_url
  description = "SQS queue URL"
}

output "sqs_queue_arn" {
  value       = local.sqs_queue_arn
  description = "SQS queue ARN"
}

output "sqs_dlq_arn" {
  value       = local.sqs_dlq_arn
  description = "SQS Dead Letter Queue ARN"
}

# ============================================================================
# Integration Summary
# ============================================================================
output "integration_summary" {
  value = {
    event_flow = "EventBridge → Lambda (primary) / SQS DLQ (fallback)"
    data_flow  = "Lambda processes events and sends to ServiceNow"
    sqs_flow   = "SQS triggers Lambda for batch processing"
    archive    = "EventBridge archives events for replay"
  }
  description = "Summary of how the three modules are integrated"
}
