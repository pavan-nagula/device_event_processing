variable "create_event_bus" {
  description = "Create a dedicated EventBridge bus (true) or reuse an existing one (false)"
  type        = bool
  default     = true
}

variable "event_bus_name" {
  description = "Name of the EventBridge bus to create or reference"
  type        = string
  default     = "org-events"
}

# -------- Org / account access policy for producers --------
variable "allow_org_id" {
  description = "If set, allow any principal from this AWS Organization ID to PutEvents to this bus"
  type        = string
  default     = null
}

variable "allow_account_ids" {
  description = "Optional list of specific AWS account IDs allowed to PutEvents to this bus"
  type        = list(string)
  default     = []
}

# -------- Rules & Targets --------
variable "rules" {
  description = <<EOT
List of rule objects:
- name                (string, required)
- description         (string, optional)
- event_pattern       (any JSON object, required)
- targets             (list of target objects, optional)

Each target supports:
- id                  (string, required)          unique per rule
- arn                 (string, optional)          direct target ARN
- ssm_param_name      (string, optional)          OR fetch ARN from SSM parameter
- type                (string, optional)          "lambda" | "sqs" | "other"
- input               (string, optional)          raw JSON sent to target (if no transformer)
- input_paths         (map(string), optional)     input transformer paths
- input_template      (string, optional)          input transformer template
- dead_letter_arn     (string, optional)          SQS DLQ ARN for THIS target
- maximum_retries     (number, optional)          1..185
- maximum_event_age   (number, optional)          60..86400 seconds
- role_arn            (string, optional)          role for some targets (e.g., SQS SendMessage cross-account)
EOT
  type = list(object({
    name          = string
    description   = optional(string)
    event_pattern = any
    targets = optional(list(object({
      id                = string
      arn               = optional(string)
      ssm_param_name    = optional(string)
      type              = optional(string, "other")
      input             = optional(string)
      input_paths       = optional(map(string))
      input_template    = optional(string)
      dead_letter_arn   = optional(string)
      maximum_retries   = optional(number)
      maximum_event_age = optional(number)
      role_arn          = optional(string)
    })), [])
  }))
  default = []
}

# -------- Archive (replay/audit) --------
variable "create_archive" {
  description = "Create an EventBridge archive for this bus"
  type        = bool
  default     = true
}

variable "archive_name" {
  description = "Archive name"
  type        = string
  default     = "org-events-archive"
}

variable "archive_retention_days" {
  description = "Retention days for archive (1..2555)"
  type        = number
  default     = 90
}

variable "archive_event_pattern" {
  description = "If set, only events matching this pattern are archived; else all events on the bus"
  type        = any
  default     = null
}

# -------- Schemas (optional) --------
variable "create_schemas_registry" {
  description = "Create a Schemas registry for this bus"
  type        = bool
  default     = false
}

variable "schemas_registry_name" {
  description = "Schemas registry name (if created)"
  type        = string
  default     = "org-events-registry"
}

variable "enable_schema_discovery" {
  description = "Enable schema discovery for the bus into the registry"
  type        = bool
  default     = false
}

variable "schemas_registry_arn" {
  description = "If NOT creating a registry, provide an existing registry ARN for discovery"
  type        = string
  default     = null
}

# -------- Tags --------
variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
