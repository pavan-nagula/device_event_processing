provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = merge(
      {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "terraform"
      },
      var.tags
    )
  }
}

# ============================================================================
# Module 1: SQS Queue and DLQ
# ============================================================================

# Create SQS module only if create_sqs is true
module "sqs" {
  count  = var.create_sqs ? 1 : 0
  source = "./sqs_terraform/modules/sqs"

  queue_name   = "${var.project_name}-${var.environment}-events"
  create_queue = var.create_sqs
}

# Get existing SQS queue details if not creating new ones
data "aws_sqs_queue" "existing" {
  count = var.create_sqs ? 0 : 1
  name  = "${var.project_name}-${var.environment}-events"
}

# Get existing DLQ details if not creating new ones
data "aws_sqs_queue" "existing_dlq" {
  count = var.create_sqs ? 0 : 1
  name  = "${var.project_name}-${var.environment}-events-dlq"
}

# Get SQS details - use newly created or existing
locals {
  sqs_queue_url = var.create_sqs ? module.sqs[0].queue_url : data.aws_sqs_queue.existing[0].url
  sqs_queue_arn = var.create_sqs ? module.sqs[0].queue_arn : data.aws_sqs_queue.existing[0].arn
  sqs_dlq_arn   = var.create_sqs ? module.sqs[0].dlq_arn : data.aws_sqs_queue.existing_dlq[0].arn
}

# ============================================================================
# Module 2: Lambda with ServiceNow Integration
# ============================================================================
module "lambda_servicenow" {
  source = "./lambda_serviceNow-main"

  region                        = var.region
  aws_profile                   = var.aws_profile
  project                       = var.project_name
  environment                   = var.environment
  tags                          = var.tags
  lambda_runtime                = var.lambda_runtime
  lambda_timeout                = var.lambda_timeout
  lambda_memory_mb              = var.lambda_memory_mb
  cloudwatch_log_retention_days = var.cloudwatch_log_retention_days

  # Use the SQS queue created by sqs module
  sqs_queue_url           = local.sqs_queue_url
  sqs_queue_arn           = local.sqs_queue_arn
  sqs_dlq_arn             = local.sqs_dlq_arn
  sqs_batch_size          = var.sqs_batch_size
  sqs_max_batching_window = var.sqs_max_batching_window

  # EventBridge integration (disabled here, handled by eventbridge module)
  create_eventbridge_rule = false
  event_pattern           = var.event_pattern

  # ServiceNow configuration
  snow_instance          = var.snow_instance
  servicenow_secret_name = var.servicenow_secret_name
  snow_table             = var.snow_table

  # Lambda resource creation control (idempotent pattern)
  create_lambda                 = var.create_lambda
  existing_lambda_function_name = var.existing_lambda_function_name

  create_lambda_kms      = var.create_lambda_kms
  create_lambda_iam      = var.create_lambda_iam
  create_lambda_loggroup = var.create_lambda_loggroup
}

# ============================================================================
# Module 3: EventBridge with org-level routing
# ============================================================================
module "eventbridge" {
  source = "./eventBridge-main/modules/eventbridge_org"

  create_event_bus  = var.create_event_bus
  event_bus_name    = var.event_bus_name
  allow_org_id      = var.allow_org_id
  allow_account_ids = var.allow_account_ids
  create_archive    = var.create_archive
  archive_name      = var.archive_name

  # Define rules that route to Lambda and SQS
  rules = [
    # Route device events to Lambda (primary)
    # Use a single target and leverage EventBridge's dead-letter support
    {
      name        = "${var.project_name}-device-events-rule"
      description = "Route device events to Lambda for ServiceNow integration"
      event_pattern = {
        source      = var.event_sources
        detail-type = var.event_detail_types
      }
      targets = [
        {
          id          = "lambda-target"
          arn         = module.lambda_servicenow.lambda_function_arn
          type        = "lambda"
          role_arn    = local.eventbridge_role_arn
          input_paths = var.lambda_input_paths
          input_tmpl  = var.lambda_input_template

          # configure DLQ on the Lambda target so only failed events are sent to SQS instead of duplicating every event
          dead_letter_arn   = local.sqs_dlq_arn
          maximum_retries   = 3
          maximum_event_age = 3600
        }
      ]
    }
  ]

  tags = var.tags
}

# ============================================================================
# IAM Role for EventBridge to access Lambda and SQS (Idempotent)
# ============================================================================
data "aws_iam_policy_document" "eventbridge_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_role" {
  count              = var.create_eventbridge_role ? 1 : 0
  name               = "${var.project_name}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume.json
  tags               = var.tags
}

data "aws_iam_role" "eventbridge_role" {
  count = var.create_eventbridge_role ? 0 : 1
  name  = "${var.project_name}-eventbridge-role"
}

locals {
  eventbridge_role_arn = var.create_eventbridge_role ? aws_iam_role.eventbridge_role[0].arn : data.aws_iam_role.eventbridge_role[0].arn
  eventbridge_role_id  = var.create_eventbridge_role ? aws_iam_role.eventbridge_role[0].id : data.aws_iam_role.eventbridge_role[0].id
}

data "aws_iam_policy_document" "eventbridge_policy" {
  # Allow Lambda invocation
  statement {
    sid    = "AllowLambdaInvoke"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      module.lambda_servicenow.lambda_function_arn
    ]
  }

  # Allow SQS SendMessage
  statement {
    sid    = "AllowSQSSendMessage"
    effect = "Allow"
    actions = [
      "sqs:SendMessage"
    ]
    resources = [
      local.sqs_queue_arn,
      local.sqs_dlq_arn
    ]
  }
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  name   = "${var.project_name}-eventbridge-policy"
  role   = local.eventbridge_role_id
  policy = data.aws_iam_policy_document.eventbridge_policy.json
}

# ============================================================================
# Lambda Permission for EventBridge to invoke it
# ============================================================================
resource "aws_lambda_permission" "allow_eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_servicenow.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge.event_bus_arn
}
