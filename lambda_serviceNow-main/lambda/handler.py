import json
import os
import logging
import urllib.request
import urllib.error
import urllib.parse
import base64
import boto3
from typing import Tuple

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client("sqs")
secrets_manager = boto3.client("secretsmanager")

QUEUE_URL = os.environ["QUEUE_URL"]
SNOW_INSTANCE = os.environ["SNOW_INSTANCE"]
# SNOW_INSTANCE = "invalid-instance"
SECRET_NAME = os.environ.get("SERVICENOW_SECRET_NAME", "servicenow/oauth_token")
SNOW_TABLE = os.environ.get("SNOW_TABLE", "incident")

# Cache for OAuth token (will be fetched on first use)
_oauth_token = None
_oauth_token_timestamp = 0

def _get_oauth_token() -> str:
    """
    Fetch OAuth token from AWS Secrets Manager.
    Returns the access token string.
    """
    global _oauth_token, _oauth_token_timestamp
    
    try:
        secret_response = secrets_manager.get_secret_value(SecretId=SECRET_NAME)
        secret = json.loads(secret_response.get("SecretString", "{}"))
        
        client_id = secret.get("client_id")
        client_secret = secret.get("client_secret")
        
        if not client_id or not client_secret:
            logger.error("Missing client_id or client_secret in secret")
            raise ValueError("Invalid ServiceNow OAuth credentials in Secrets Manager")
        
        # Request OAuth token from ServiceNow
        token_url = f"https://{SNOW_INSTANCE}.service-now.com/oauth_token.do"
        auth_string = f"{client_id}:{client_secret}"
        
        post_data = urllib.parse.urlencode({
            "grant_type": "client_credentials"
        }).encode("utf-8")
        
        headers = {
            "Content-Type": "application/x-www-form-urlencoded",
            "Authorization": f"Basic {__import__('base64').b64encode(auth_string.encode()).decode()}"
        }
        
        req = urllib.request.Request(token_url, data=post_data, headers=headers, method="POST")
        
        with urllib.request.urlopen(req, timeout=10) as resp:
            token_response = json.loads(resp.read().decode("utf-8"))
            _oauth_token = token_response.get("access_token")
            
            if not _oauth_token:
                logger.error("Failed to get OAuth token from ServiceNow")
                raise ValueError("No access token in ServiceNow response")
            
            logger.info("Successfully obtained OAuth token from ServiceNow")
            return _oauth_token
            
    except Exception as e:
        logger.error(f"Error fetching OAuth token: {str(e)}")
        raise

def _servicenow_url() -> str:
    # Example: https://dev12345.service-now.com/api/now/table/incident
    return f"https://{SNOW_INSTANCE}.service-now.com/api/now/table/{SNOW_TABLE}"

def create_servicenow_record(payload: dict) -> Tuple[bool, str]:
    """
    Create *or update* a record in ServiceNow using OAuth token.

    The original version always POSTed to the table which resulted in a
    new incident each time.  This helper now looks for a few well‑known
    keys on `payload` (`sys_id` or `number`) and, if present, converts the
    request into an update (PATCH) against the existing record.  When the
    identifier is missing we fall back to a standard POST so that new
    records continue to be created just as before.

    Returns a tuple `(success, message)` like the previous implementation.
    Uses the standard library `urllib` to avoid adding dependencies.
    """
    try:
        # Get OAuth token from Secrets Manager
        token = _get_oauth_token()
        
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Authorization": f"Bearer {token}"
        }

        # Extract detail from EventBridge event
        detail = payload.get("detail", payload)  # payload might be just the detail, or it might be the full event
        if isinstance(detail, str):
            detail = json.loads(detail)

        logger.info(f"Processing payload. Has detail field: {'detail' in payload}, sys_id: {detail.get('sys_id')}, number: {detail.get('number')}")

        # Build a clean, readable description from the detail fields
        # Extract only the relevant business data, not the event metadata
        description_lines = []
        for key, value in detail.items():
            # Skip internal fields
            if key not in ['sys_id', 'number']:
                description_lines.append(f"• {key}: {value}")
        
        clean_description = "\n".join(description_lines) if description_lines else json.dumps(detail, ensure_ascii=False)
        
        # Build short description - prioritize 'note' field, then 'message', then status/event info
        short_desc = (
            detail.get('note') or
            detail.get('message') or
            detail.get('title') or
            f"[{payload.get('source', 'Event')}] {payload.get('detail-type', 'Alert')}"
        )
        
        # map event fields to ServiceNow payload (customise as required)
        body = {
            "short_description": short_desc,
            "description": clean_description
        }

        # Check if this is a resolution/closure event
        # Handle various event types that indicate resolution
        state = detail.get('state', '').upper()
        status = detail.get('status', '').upper()
        is_resolved = detail.get('resolved', False)
        is_recovery = detail.get('device_recovered', False)
        
        if any([
            state == 'RESOLVED',
            state == 'CLOSED',
            status == 'RESOLVED',
            status == 'CLOSED',
            is_resolved,
            is_recovery
        ]):
            # This is a resolution event - set status to closed
            # Using ServiceNow standard fields for closing incidents
            body["state"] = 7  # 7 = Closed state in ServiceNow
            body["caller_id"] = "ITIL User"  # Use ITIL User as the caller
            body["resolution_code"] = "Solved"  # Set resolution code to Solved
            logger.info(f"Detected incident closure event. Setting state=7, caller_id=ITIL User, resolution_code=Solved")

        # determine whether this is an update or a create
        method = "POST"
        url = _servicenow_url()

        # if we have a sys_id explicitly use it; ServiceNow prefers PATCH
        if detail.get("sys_id"):
            method = "PATCH"
            url = f"{url}/{detail['sys_id']}"
            logger.info(f"Update mode: Using sys_id, method={method}, url={url}")
        # alternatively support looking up by number if that's supplied
        elif detail.get("number"):
            incident_number = str(detail['number']).strip()
            logger.info(f"Looking up incident by number: {incident_number}")
            # issue a query to find the record first and then PATCH it
            # (simple approach: assume number uniquely identifies a single record)
            query_url = f"{url}?sysparm_query=number={urllib.parse.quote(incident_number)}&sysparm_limit=1"
            logger.info(f"Query URL: {query_url}")
            try:
                req = urllib.request.Request(query_url, headers=headers, method="GET")
                with urllib.request.urlopen(req, timeout=10) as resp:
                    if resp.getcode() == 200:
                        response_data = json.loads(resp.read().decode())
                        records = response_data.get("result", [])
                        logger.info(f"Lookup response: found {len(records)} records")
                        if records:
                            method = "PATCH"
                            found_sys_id = records[0]['sys_id']
                            url = f"{url}/{found_sys_id}"
                            logger.info(f"Update mode: Found existing incident {incident_number}, method={method}, sys_id={found_sys_id}")
                        else:
                            logger.info(f"No incident found with number {incident_number}, will create new")
            except urllib.error.HTTPError as lookup_error:
                logger.warning(f"Lookup failed with HTTP {lookup_error.code}, will try to create new record")
        else:
            logger.info("Create mode: No sys_id or number provided, will create new incident")

        data = json.dumps(body).encode("utf-8")

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = resp.getcode()
            resp_body = resp.read().decode("utf-8")
            if 200 <= status < 300:
                action = "updated" if method != "POST" else "created"
                logger.info("ServiceNow record %s. Status=%s Body=%s", action, status, resp_body)
                return True, f"ServiceNow record {action}"
            else:
                logger.error("ServiceNow returned non-2xx. Status=%s Body=%s", status, resp_body)
                return False, f"ServiceNow error: HTTP {status}"
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8") if e.fp else str(e)
        logger.exception("HTTPError calling ServiceNow: %s | Body=%s", e, err_body)
        return False, f"HTTPError: {e.code}"
    except urllib.error.URLError as e:
        logger.exception("URLError calling ServiceNow: %s", e)
        return False, "URLError"
    except Exception as e:
        logger.exception("Unexpected error calling ServiceNow: %s", e)
        return False, "UnexpectedError"

def send_to_sqs(message: dict) -> str:
    response = sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(message)
    )
    msg_id = response.get("MessageId")
    logger.info("Sent to SQS. MessageId=%s", msg_id)
    return msg_id

def is_sqs_event(event: dict) -> bool:
    return isinstance(event, dict) and "Records" in event and len(event["Records"]) > 0 and \
           event["Records"][0].get("eventSource") == "aws:sqs"

def handle_eventbridge_event(event: dict):
    """
    Branch 1: EventBridge → Lambda
    IF ServiceNow create succeeds: OK
    ELSE: enqueue the payload to SQS
    """
    logger.info("Processing EventBridge event")
    success, msg = create_servicenow_record(event)
    if success:
        logger.info("ServiceNow OK (EventBridge path)")
        return {"status": "ok", "path": "eventbridge", "servicenow": "created"}
    else:
        logger.warning("ServiceNow failed (EventBridge path). Sending to SQS. Reason=%s", msg)
        message_body = {
            "retry_source": "sqs",
            "original_event": event
        }
        message_id = send_to_sqs(message_body)
        return {"status": "queued", "path": "eventbridge", "messageId": message_id}

def handle_sqs_event(event: dict):
    """
    Branch 2: SQS → Lambda
    For each record, try ServiceNow.
    IF it fails, raise to let SQS/Lambda retry & DLQ handle it.
    """
    logger.info("Processing SQS batch with %d record(s)", len(event["Records"]))
    failures = []

    for rec in event["Records"]:
        try:
            body = json.loads(rec["body"])
        except json.JSONDecodeError:
            logger.error("Invalid JSON in SQS message body. MessageId=%s Body=%s", rec.get("messageId"), rec.get("body"))
            # Fail this record; it will retry/then DLQ
            failures.append({"itemIdentifier": rec["messageId"]})
            continue

        payload = body.get("original_event") or body  # backward-compatible
        success, msg = create_servicenow_record(payload)
        if not success:
            logger.error("ServiceNow failed (SQS path). MessageId=%s Reason=%s", rec.get("messageId"), msg)
            # To keep the message in the queue for retry, mark as failed
            failures.append({"itemIdentifier": rec["messageId"]})
        else:
            logger.info("ServiceNow OK (SQS path). MessageId=%s", rec.get("messageId"))

    # Partial batch response (Lambda SQS feature). If any failed, return their IDs.
    # If none failed, return empty list.
    return {"batchItemFailures": failures}

def lambda_handler(event, context):
    """
    Two if/else branches as requested:

    1) IF EventBridge event: try ServiceNow; ELSE send to SQS
    2) IF SQS event: try ServiceNow per message; ELSE failure keeps in queue for retry/DLQ
    """
    logger.info("Received event: %s", json.dumps(event))

    # --- IF/ELSE #1: Determine source ---
    if is_sqs_event(event):
        # SQS → Lambda branch
        result = handle_sqs_event(event)
        # Partial batch response expected by SQS → Lambda
        return result
    else:
        # EventBridge → Lambda branch
        result = handle_eventbridge_event(event)
        return {
            "statusCode": 200,
            "body": json.dumps(result)
        }