locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ------------------------------------------------------------
# detect if the lambda already exists in AWS so that we can
# automatically skip creation (avoids ResourceConflictException).
# an external data source executes a small python snippet calling
# the AWS CLI, which returns whether the function name is present.

data "external" "lambda_exists" {
  program = ["python", "-c", <<EOF
import sys, json, subprocess
query = json.load(sys.stdin)
name = query.get("function_name")
region = query.get("region")
profile = query.get("profile") or None
result = {"exists": "false"}
cmd = ["aws", "lambda", "get-function", "--function-name", name]
if region:
    cmd += ["--region", region]
if profile:
    cmd += ["--profile", profile]
try:
    subprocess.check_call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result["exists"] = "true"
except Exception:
    pass
print(json.dumps(result))
EOF
  ]

  query = {
    function_name = "${local.name_prefix}-fn"
    region        = var.region
    profile       = var.aws_profile
  }
}

locals {
  lambda_exists           = data.external.lambda_exists.result.exists == "true"
  effective_create_lambda = var.create_lambda && !local.lambda_exists
}

# --- KMS for Lambda environment variable encryption (idempotent) ---
resource "aws_kms_key" "lambda_env" {
  count               = var.create_lambda_kms ? 1 : 0
  description         = "KMS CMK for encrypting Lambda environment variables for ${local.name_prefix}"
  enable_key_rotation = true
}

data "aws_kms_key" "lambda_env" {
  count  = var.create_lambda_kms ? 0 : 1
  key_id = "alias/${local.name_prefix}-lambda-env"
}

locals {
  lambda_kms_key_id = var.create_lambda_kms ? aws_kms_key.lambda_env[0].key_id : data.aws_kms_key.lambda_env[0].key_id
  lambda_kms_arn    = var.create_lambda_kms ? aws_kms_key.lambda_env[0].arn : data.aws_kms_key.lambda_env[0].arn
}

resource "aws_kms_alias" "lambda_env_alias" {
  count         = var.create_lambda_kms ? 1 : 0
  name          = "alias/${local.name_prefix}-lambda-env"
  target_key_id = local.lambda_kms_key_id
}

# --- SQS Configuration (provided by parent module) ---
# The Lambda module expects SQS queue information to be passed in via variables.
# This module does NOT create SQS queues - they are managed by the root module.
# The root module creates the SQS queues and passes their URLs/ARNs to this module.

# --- IAM Role for Lambda (idempotent) ---
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  count              = var.create_lambda_iam ? 1 : 0
  name               = "${local.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_role" "lambda_exec" {
  count = var.create_lambda_iam ? 0 : 1
  name  = "${local.name_prefix}-lambda-exec"
}

locals {
  lambda_role_arn = var.create_lambda_iam ? aws_iam_role.lambda_exec[0].arn : data.aws_iam_role.lambda_exec[0].arn
  lambda_role_id  = var.create_lambda_iam ? aws_iam_role.lambda_exec[0].id : data.aws_iam_role.lambda_exec[0].id
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid = "AllowCloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # Allow sending to the queue
  statement {
    sid     = "AllowSendMessageToQueue"
    actions = ["sqs:SendMessage"]
    resources = [
      var.sqs_queue_arn
    ]
  }

  # Permissions needed when Lambda is triggered by SQS (service polls on your function's role)
  statement {
    sid = "AllowPollAndDeleteFromQueue"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [
      var.sqs_queue_arn
    ]
  }

  statement {
    sid = "AllowKMSDecryptLambdaEnv"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]
    resources = [local.lambda_kms_arn]
  }

  # Allow reading ServiceNow OAuth credentials from Secrets Manager
  statement {
    sid = "AllowReadSecretsManager"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      "arn:aws:secretsmanager:*:*:secret:servicenow/*"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_inline" {
  name   = "${local.name_prefix}-lambda-inline"
  role   = local.lambda_role_id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# --- Package Lambda code ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda/build/lambda.zip"
}

# --- CloudWatch Log Group for Lambda with retention (idempotent) ---
resource "aws_cloudwatch_log_group" "lambda" {
  count             = var.create_lambda_loggroup ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-fn"
  retention_in_days = var.cloudwatch_log_retention_days
}

# Reference existing log group if not creating
data "aws_cloudwatch_log_group" "lambda" {
  count = var.create_lambda_loggroup ? 0 : 1
  name  = "/aws/lambda/${local.name_prefix}-fn"
}

locals {
  log_group_name = var.create_lambda_loggroup ? aws_cloudwatch_log_group.lambda[0].name : data.aws_cloudwatch_log_group.lambda[0].name
}

# --- Lambda Function -----------------------------------------------------
# the module can either create a new function or reference an existing one. the
# "create_lambda" boolean determines the behavior; when false the resource is
# skipped and a data lookup is used instead.  callers must also supply
# existing_lambda_function_name in that case.

data "aws_lambda_function" "existing" {
  count         = local.effective_create_lambda ? 0 : 1
  function_name = local.lambda_exists ? "${local.name_prefix}-fn" : var.existing_lambda_function_name
}

locals {
  # name/arn used throughout the module; pick created resource when
  # we're going to make one, otherwise use the looked‑up function.
  lambda_function_name = local.effective_create_lambda ? "${local.name_prefix}-fn" : (var.existing_lambda_function_name != "" ? var.existing_lambda_function_name : "${local.name_prefix}-fn")
  lambda_function_arn  = local.effective_create_lambda ? aws_lambda_function.fn[0].arn : data.aws_lambda_function.existing[0].arn
}

resource "aws_lambda_function" "fn" {
  count         = local.effective_create_lambda ? 1 : 0
  function_name = local.lambda_function_name
  role          = local.lambda_role_arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_mb

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Encrypt environment vars with the KMS CMK
  kms_key_arn = local.lambda_kms_arn

  environment {
    variables = {
      # SQS
      QUEUE_URL = var.sqs_queue_url

      # ServiceNow OAuth (credentials retrieved from Secrets Manager at runtime)
      SNOW_INSTANCE          = var.snow_instance
      SERVICENOW_SECRET_NAME = var.servicenow_secret_name
      SNOW_TABLE             = var.snow_table
    }
  }
}

# --- EventBridge Rule & Target (Event → Lambda) ---
resource "aws_cloudwatch_event_rule" "rule" {
  count         = var.create_eventbridge_rule ? 1 : 0
  name          = "${local.name_prefix}-rule"
  event_pattern = jsonencode(var.event_pattern)
  lifecycle {
    ignore_changes = [event_pattern]
  }
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  count     = var.create_eventbridge_rule ? 1 : 0
  rule      = aws_cloudwatch_event_rule.rule[0].name
  target_id = "invoke-${local.lambda_function_name}"
  arn       = local.lambda_function_arn
}

# Allow EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.create_eventbridge_rule ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = local.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rule[0].arn
}

# --- Connect SQS → Lambda (event source mapping) ---
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn                   = var.sqs_queue_arn
  function_name                      = local.lambda_function_arn
  batch_size                         = var.sqs_batch_size
  maximum_batching_window_in_seconds = var.sqs_max_batching_window
  enabled                            = true

  # Report batch item failures so failed items are sent to DLQ via queue's redrive policy
  function_response_types = ["ReportBatchItemFailures"]
}
