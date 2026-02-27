output "event_bus_name" {
  value       = local.bus_name
  description = "Event bus name (created or referenced)"
}

output "event_bus_arn" {
  value       = local.bus_arn
  description = "Event bus ARN (created or referenced)"
}

output "rule_names" {
  value       = keys(aws_cloudwatch_event_rule.rules)
  description = "Names of all rules created"
}

output "rule_arns" {
  value       = { for k, v in aws_cloudwatch_event_rule.rules : k => v.arn }
  description = "Map of rule name -> rule ARN"
}

output "archive_arn" {
  value       = try(aws_cloudwatch_event_archive.this[0].arn, null)
  description = "Archive ARN if created"
}
