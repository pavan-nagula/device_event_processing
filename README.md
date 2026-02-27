# Device Event Processing

This repository implements a workflow that captures device events, processes them through AWS EventBridge and Lambda, and creates incident records in **ServiceNow**. It uses Terraform modules to provision all AWS resources.

## Architecture Overview

### 1. Module: `sqs`
**Source:** `sqs`

#### Creates:
- Primary SQS queue
- Dead Letter Queue (DLQ)

#### Outputs:
- queue_url
- queue_arn
- dlq_arn

---

### 2. Module: `lambda_servicenow`
**Source:** `lambda_serviceNow-main`
**Dependencies:** Uses SQS outputs (`module.sqs.queue_url`, etc.)

#### Creates:
- KMS key + alias
- IAM role & policy
- CloudWatch log group
- Lambda function (`handler.py`)

#### Additional Behavior:
- Event source mapping → Lambda triggered by SQS
- Optional EventBridge rule (`create_eventbridge_rule = true`)
- Retrieves OAuth credentials from Secrets Manager
- Sets environment variables for SQS + ServiceNow

**Note:** This module does **not** create SSM parameters.

---

### 3. Module: `eventbridge`
**Source:** `eventbridge`

#### Takes Inputs From:
- module.lambda_servicenow.lambda_function_arn
- module.sqs.queue_arn
- module.sqs.dlq_arn

#### Creates:
- Event bus
- Rules
- IAM role/policy
- aws_lambda_permission

#### SSM Parameter Logic:
- If both ARN + ssm_param_name are provided → creates SSM String parameter
- If only ssm_param_name → reads ARN at apply time

---

## Passing Values / Variables
- Configuration is defined in variables.tf and set via terraform.tfvars
- Module outputs referenced directly
- Provider default_tags merges project + resource tags

---

## Prerequisites
- AWS permissions for SQS, Lambda, IAM, KMS, EventBridge, Secrets Manager

---


# Event Processing Flow

## Scenario 1: Happy Path (Everything Works)
1. Event arrives → sent to EventBridge
2. EventBridge rule matches → sent to Lambda
3. Lambda receives payload
4. Lambda calls ServiceNow → Incident created
5. Process completes successfully

## Scenario 2: Error Path (ServiceNow Down)
1. Event arrives
2. EventBridge routes event
3. Lambda processes event
4. ServiceNow call fails
5. Lambda stores failed message in SQS
6. Lambda retries via event source mapping
   - Success: Incident created
   - Failure after retries → message moved to DLQ
