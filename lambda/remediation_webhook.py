"""Auto-remediation webhook for monitoring alerts (Dynatrace, Datadog, etc.).

POST /remediate with header `x-webhook-token: <secret>` and body
{"instance_id": "i-...", "cpu": 3.2}

- CPU below the low threshold: stop the instance (only if it is tagged
  <AUTO_STOP_TAG>=true, so alerts can never stop untagged/production instances)
- CPU above the high threshold: report that a scale-up is needed
The shared secret is read from AWS Secrets Manager.
"""

import hmac
import json
import os

import boto3

ec2 = boto3.client("ec2")
secrets = boto3.client("secretsmanager")

SECRET_ARN = os.environ["WEBHOOK_SECRET_ARN"]
AUTO_STOP_TAG = os.environ.get("AUTO_STOP_TAG", "AutoStop")
LOW_CPU = float(os.environ.get("LOW_CPU_THRESHOLD", "5"))
HIGH_CPU = float(os.environ.get("HIGH_CPU_THRESHOLD", "80"))

_token = None


def webhook_token():
    global _token
    if _token is None:
        _token = secrets.get_secret_value(SecretId=SECRET_ARN)["SecretString"]
    return _token


def lambda_handler(event, context):
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    supplied = headers.get("x-webhook-token", "")
    if not hmac.compare_digest(supplied.encode(), webhook_token().encode()):
        return respond(401, {"error": "unauthorized"})

    try:
        body = json.loads(event.get("body") or "{}")
        instance_id = body["instance_id"]
        cpu = float(body["cpu"])
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        return respond(400, {"error": "body must be JSON with instance_id and numeric cpu"})

    if cpu < LOW_CPU:
        if not is_opted_in(instance_id):
            action = "skipped_not_opted_in"
        else:
            ec2.stop_instances(InstanceIds=[instance_id])
            action = "stopped"
    elif cpu > HIGH_CPU:
        action = "scale_up_needed"
    else:
        action = "no_action"

    print(json.dumps({"instance": instance_id, "cpu": cpu, "action": action}))
    return respond(200, {"instance": instance_id, "action": action})


def is_opted_in(instance_id):
    try:
        reservations = ec2.describe_instances(InstanceIds=[instance_id])["Reservations"]
    except ec2.exceptions.ClientError:
        return False
    for reservation in reservations:
        for instance in reservation["Instances"]:
            tags = {t["Key"]: t["Value"] for t in instance.get("Tags", [])}
            if tags.get(AUTO_STOP_TAG, "").lower() == "true":
                return True
    return False


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
