locals {
  # Flatten (rule, target) pairs for easier resource creation
  flat_targets = flatten([
    for r in var.rules : [
      for t in coalesce(r.targets, []) : {
        rule_name   = r.name
        id          = t.id
        key         = "${r.name}:${t.id}"
        arn         = try(t.arn, null)
        ssm_param   = try(t.ssm_param_name, null)
        type        = try(t.type, "other")
        input       = try(t.input, null)
        input_paths = try(t.input_paths, null)
        input_tmpl  = try(t.input_template, null)
        dlq_arn     = try(t.dead_letter_arn, null)
        max_retries = try(t.maximum_retries, null)
        max_age     = try(t.maximum_event_age, null)
        role_arn    = try(t.role_arn, null)
      }
    ]
  ])

  # targets that need a parameter lookup (no ARN provided directly)
  targets_need_ssm = {
    for t in local.flat_targets : t.key => t
    if t.ssm_param != null && (t.arn == null || t.arn == "")
  }

  # optionally create SSM parameters when both ARN and ssm_param are given
  ssm_to_create = {
    for t in local.flat_targets : t.key => t
    if t.ssm_param != null && t.arn != null && t.arn != ""
  }
}

# Create or look up the bus
resource "aws_cloudwatch_event_bus" "this" {
  count = var.create_event_bus ? 1 : 0
  name  = var.event_bus_name
  tags  = var.tags
}

data "aws_cloudwatch_event_bus" "this" {
  count = var.create_event_bus ? 0 : 1
  name  = var.event_bus_name
}

locals {
  bus_name = var.create_event_bus ? aws_cloudwatch_event_bus.this[0].name : data.aws_cloudwatch_event_bus.this[0].name
  bus_arn  = var.create_event_bus ? aws_cloudwatch_event_bus.this[0].arn : data.aws_cloudwatch_event_bus.this[0].arn
}

# -------- Bus policies (Org / accounts) --------
# Build one policy containing org and/or account statements
data "aws_iam_policy_document" "event_bus" {
  # Org-wide PutEvents (optional)
  dynamic "statement" {
    for_each = var.allow_org_id != null ? [var.allow_org_id] : []
    content {
      sid       = "AllowOrgPutEvents"
      effect    = "Allow"
      actions   = ["events:PutEvents"]
      resources = [local.bus_arn]

      principals {
        type        = "AWS"
        identifiers = ["*"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = [statement.value]
      }
    }
  }

  # Per-account PutEvents (optional)
  dynamic "statement" {
    for_each = toset(var.allow_account_ids)
    content {
      sid       = "AllowAccount${statement.value}PutEvents"
      effect    = "Allow"
      actions   = ["events:PutEvents"]
      resources = [local.bus_arn]

      principals {
        type        = "AWS"
        identifiers = [statement.value]
      }
    }
  }
}

# Apply combined policy to the bus (create only if we added any statement)
resource "aws_cloudwatch_event_bus_policy" "this" {
  count          = (var.allow_org_id != null || length(var.allow_account_ids) > 0) ? 1 : 0
  event_bus_name = local.bus_name
  policy         = data.aws_iam_policy_document.event_bus.json
}
# -------- Rules --------
resource "aws_cloudwatch_event_rule" "rules" {
  for_each       = { for r in var.rules : r.name => r }
  name           = each.value.name
  description    = try(each.value.description, null)
  event_bus_name = local.bus_name
  event_pattern  = jsonencode(each.value.event_pattern)
  tags           = var.tags
  lifecycle {
    ignore_changes = [event_pattern]
  }
}

# Optionally create missing parameters when the ARN is supplied directly
resource "aws_ssm_parameter" "auto" {
  for_each = local.ssm_to_create

  name  = each.value.ssm_param
  type  = "String"
  value = each.value.arn
}

# Resolve target ARNs from SSM (optional)
data "aws_ssm_parameter" "target_arns" {
  for_each = local.targets_need_ssm
  name     = each.value.ssm_param

  # ensure we create before attempting to read (handles same-run cases)
  depends_on = [aws_ssm_parameter.auto]
}

# -------- Targets (per rule) --------
resource "aws_cloudwatch_event_target" "targets" {
  for_each = { for t in local.flat_targets : t.key => t }

  rule           = aws_cloudwatch_event_rule.rules[each.value.rule_name].name
  event_bus_name = local.bus_name

  target_id = replace(each.key, ":", "-")

  arn      = coalesce(each.value.arn, try(data.aws_ssm_parameter.target_arns[each.key].value, null))
  role_arn = try(each.value.role_arn, null)

  # Input Transformer (paths + template) OR raw input
  dynamic "input_transformer" {
    for_each = (each.value.input_paths != null && each.value.input_tmpl != null) ? [1] : []
    content {
      input_paths    = each.value.input_paths
      input_template = each.value.input_tmpl
    }
  }

  input = (each.value.input_paths == null && each.value.input_tmpl == null) ? try(each.value.input, null) : null

  # Retry & Max Age
  dynamic "retry_policy" {
    for_each = (each.value.max_retries != null || each.value.max_age != null) ? [1] : []
    content {
      maximum_retry_attempts       = try(each.value.max_retries, null)
      maximum_event_age_in_seconds = try(each.value.max_age, null)
    }
  }

  # Target DLQ (SQS)
  dynamic "dead_letter_config" {
    for_each = each.value.dlq_arn != null ? [1] : []
    content {
      arn = each.value.dlq_arn
    }
  }
  lifecycle {
    ignore_changes = [input, input_transformer]
  }
}

# -------- Archive (optional) --------
resource "aws_cloudwatch_event_archive" "this" {
  count            = var.create_archive ? 1 : 0
  name             = var.archive_name
  description      = "Archive for ${local.bus_name}"
  retention_days   = var.archive_retention_days
  event_source_arn = local.bus_arn
  event_pattern    = var.archive_event_pattern == null ? null : jsonencode(var.archive_event_pattern)

}

# -------- Schemas (optional) --------
resource "aws_schemas_registry" "this" {
  count       = var.create_schemas_registry ? 1 : 0
  name        = var.schemas_registry_name
  description = "Registry for ${local.bus_name}"
  tags        = var.tags
}

resource "aws_schemas_discoverer" "this" {
  count       = var.enable_schema_discovery ? 1 : 0
  source_arn  = local.bus_arn
  description = "Discoverer for ${local.bus_name}"
  tags        = var.tags
}
