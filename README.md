# Device Event Processing

This repository provisions an AWS event pipeline that ingests device events, processes them with Lambda, and creates or updates records in ServiceNow.

## Architecture Overview

### 1) SQS Module

Root call: `module "sqs"`  
Source: `./sqs_terraform/modules/sqs`

Creates or references:

- Primary SQS queue
- Dead Letter Queue (DLQ)

Used by:

- Lambda event source mapping for retry processing

### 2) Lambda + ServiceNow Module

Root call: `module "lambda_servicenow"`  
Source: `./lambda_serviceNow-main`

Creates or references:

- Lambda function and deployment package
- IAM role/policies
- KMS key/alias for Lambda env encryption
- CloudWatch log group

Behavior:

- Consumes messages from SQS via event source mapping
- Reads ServiceNow OAuth credentials from AWS Secrets Manager
- Calls ServiceNow API to create/update records

### 3) EventBridge Org Module

Root call: `module "eventbridge"`  
Source: `./eventBridge-main/modules/eventbridge_org`

Creates or references:

- Event bus
- Event rule(s) and target(s)
- Optional archive for replay

In this stack, EventBridge routes matched events to Lambda.

### 4) Root-Level Integration Resources

The root Terraform also creates integration resources outside modules:

- EventBridge IAM role and inline policy
- Lambda permission for EventBridge invoke

## Event Processing Flow

### Scenario 1: Happy Path

1. Producer publishes event to EventBridge bus.
2. Rule matches by `source` and `detail-type`.
3. EventBridge invokes Lambda target.
4. Lambda sends create/update request to ServiceNow.
5. Flow completes.

### Scenario 2: ServiceNow/API Failure

1. EventBridge invokes Lambda.
2. Lambda fails to write to ServiceNow.
3. Lambda enqueues payload into the main SQS queue.
4. SQS mapping re-invokes Lambda for retry attempts.
5. After max receives, message moves to DLQ.

### EventBridge Target Retry/DLQ

The EventBridge target itself is also configured with retry policy and target-level DLQ.

## Configuration

- Inputs are defined in `variables.tf` and typically set in `terraform.tfvars`.
- Provider `default_tags` merges base tags with custom tags.

## Prerequisites

- AWS permissions for EventBridge, Lambda, IAM, SQS, KMS, CloudWatch Logs, and Secrets Manager.
