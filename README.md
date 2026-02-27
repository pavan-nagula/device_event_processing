Device Event Processing
This repo is designed to capture device events and create incident records in ServiceNow. 
Workflow

1.	Module sqs 
  o	Source: sqs 
  o	Creates a primary queue and a dead letter queue.
  o	Exposes three outputs: queue_url, queue_arn, dlq_arn.

2.	Module lambda_servicenow
  o	Source: lambda_serviceNow-main 
  o	Depends on the SQS outputs – you can see them passed in as sqs_queue_url = module.sqs.queue_url etc.
  o	Creates a KMS key/alias, IAM role & policy, CloudWatch log group and the
  Lambda function itself (packaged from handler.py).
  o	Also wires an event source mapping so the function is triggered from the
  queue, and (optionally) creates its own EventBridge rule if
  create_eventbridge_rule is true.
  o	Environment variables include the queue URL and the ServiceNow settings
  the code fetches OAuth credentials from Secrets Manager.
  o	It does not create any SSM parameters – the only SSM interaction is done
  later in the EventBridge module.

3.	Module eventbridge
  o	Source: eventbridge 
  o	Takes inputs from both previous modules:
     module.lambda_servicenow.lambda_function_arn (for the rule target)
     module.sqs.queue_arn and module.sqs.dlq_arn (for the DLQ target).
  o	Builds an event bus/rules and – in this root deployment – a single rule that
  routes device events to the Lambda and, on failure, to the DLQ.
  o	In addition the root config creates an IAM role/policy and a
  aws_lambda_permission resource so EventBridge can invoke the function.
  
  The EventBridge module has extra logic around SSM parameters:
  o	If you supply a target record with both an arn and ssm_param_name
  the module will create a String parameter containing that ARN.
  o	If you supply only ssm_param_name (no ARN), the module will read the
  ARN at apply time.
  This makes it easy to decouple the bus from the exact resource ARN or to
  publish the ARN for use by other stacks. (See the targets_need_ssm and
  aws_ssm_parameter resources inside the module.)

Passing values/variables
  •	All top level configuration (region, project/environment names, timeouts,
  etc.) come from var …  you set them via terraform.tfvars.
  •	Outputs from one module are simply referenced in another (module.sqs.queue_arn,
  module.lambda_servicenow.lambda_function_name, …). Terraform automatically
  adds the necessary depends_on relationships.
  •	The provider’s default_tags merge the per resource tags with whatever you
  pass in var.tags.
  
Prerequisites
  •	AWS credentials with permissions to create SQS queues, Lambda, IAM roles,
  EventBridge resources, KMS keys, Secrets Manager, ….
  •	Nothing else needs to exist in advance – the code creates the queues and
  Lambda function for you.
  •	If you want the ARNs stored in Systems Manager, you must supply
  ssm_param_name when defining a target, the module will handle the rest.
  
Execution
Run terraform init then terraform apply.
The code will create the Lambda function and its ARN and, if you’ve opted
into the SSM behaviour on the EventBridge side, will also write/read the
parameter for you. No manual provisioning of the function/ARN is required.

Step-by-Step Flow (In two different Scenarios)
Scenario 1: Happy Path (Everything Works)
1️⃣  EVENT ARRIVES
    └─ A sensor detects high temperature: 95°C
    └─ Sends this to AWS EventBridge as a message

2️⃣  EVENTBRIDGE CHECKS THE RULES
    └─ Question: "Is this event from device.iot or device.sensor?"
    └─ Question: "Is it a device-alert or device-reading?"
    └─ Answer: "Yes! Send it to Lambda"

3️⃣  LAMBDA WORKER RECEIVES IT
    └─ Receives: {"device_id": "sensor-001", "temperature": 95}
    └─ Says: "Let me process this"

4️⃣  LAMBDA CALLS SERVICENOW
    └─ Gets secure credentials from AWS Secrets Manager
    └─ Says: "Create a new incident"
    └─ ServiceNow responds: "✓ Problem recorded as INC0123456"

5️⃣  LAMBDA SAYS "SUCCESS"  
    └─ Event is complete
    └─ Nothing goes to SQS (no backup needed)

Scenario 2: ServiceNow is Busy (Error Path)
1️⃣  EVENT ARRIVES
    └─ Same as before

2️⃣  EVENTBRIDGE ROUTES IT
    └─ Same as before

3️⃣  LAMBDA RECEIVES EVENT
    └─ Same as before

4️⃣  LAMBDA TRIES SERVICENOW - BUT IT FAILS ❌
    └─ ServiceNow is down, or credentials issue, or timeout
    └─ Lambda says: "I can't reach ServiceNow!"

5️⃣  LAMBDA SAVES TO SQS QUEUE (BACKUP)
    └─ Puts the message in a waiting area (SQS queue)
    └─ Says: "I'll try again later"
 
6️⃣  LAMBDA EVENT SOURCE MAPPING KICKS IN
    └─ Lambda is also listening to the SQS queue
    └─ Every few seconds, it checks: "Any messages in the queue?"
    └─ Finds the failed message
    └─ Tries again: "Can I reach ServiceNow now?"
    └─ If successful: ✓ Created in ServiceNow
    └─ If still fails (after 3 attempts): Moves to Dead Letter Queue (DLQ)


