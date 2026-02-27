# EventBridge Org Module (EventBridge-only)

This repo provides an **EventBridge-only Terraform module** for org-level routing:

- Create/reuse **Event Bus**
- **Bus resource policies** (Org ID / allowed accounts)
- **Multiple rules** with **event-pattern filtering**
- Per-target **retry policy** and **DLQ** (SQS)
- **Archive** for replay/audit
- Optional **Schemas** (registry + discovery)
- **SSM** lookup for target ARNs (can auto‑create the parameter if you also supply an ARN)
- **No Lambda/SQS/IAM created here** (owned by other teams)

> **Tip:** target definitions may supply both `arn` and `ssm_param_name`. In
> that case the module writes the ARN into Parameter Store and then reads it
> back, avoiding a separate manual step.

## Quickstart (local tooling)

```bash
pip install pre-commit --upgrade
pre-commit install

make all      # init + fmt + tflint + validate
```

## Test by sending a sample event

```bash
aws events put-events --region us-east-1 --entries '[
  {
    "Source":"my.app",
    "DetailType":"app.error",
    "Detail":"{"env":"dev","message":"simulated error"}",
    "EventBusName":"org-events"
  }
]'
```

## Hand-offs to other teams

- **Lambda owners**: add `aws_lambda_permission` allowing `events.amazonaws.com` with `source_arn` = rule ARN (output `rule_arns`).
- **SQS owners**: provide `role_arn` for EventBridge to `sqs:SendMessage` to the queue and its **DLQ**.
- **Producers**: publish using `events:PutEvents` (granted via Org ID or account allow-list on the bus).
