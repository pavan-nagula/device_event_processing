import os
import boto3
 
def lambda_handler(event, context):
    sqs = boto3.client('sqs')
    queue_url = os.environ['QUEUE_URL']  # dynamic from Terraform
 
    # Receive up to 10 messages
    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=10,
        WaitTimeSeconds=0
    )
 
    if 'Messages' in response:
        for msg in response['Messages']:
            # Here you can implement your payment processing logic
            print(f"Processing message: {msg['Body']}")
 
            # Delete message after processing
            sqs.delete_message(
                QueueUrl=queue_url,
                ReceiptHandle=msg['ReceiptHandle']
            )
 
    return {"status": "processed", "messages": len(response.get('Messages', []))}