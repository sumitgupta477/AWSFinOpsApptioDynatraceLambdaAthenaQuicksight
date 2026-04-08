import json
import boto3

ec2 = boto3.client('ec2')

def handler(event, context):
    body = json.loads(event['body'])

    # Example: extract instance from Datadog alert
    instance_id = body.get("instance_id")
    cpu = body.get("cpu")

    if not instance_id:
        return {"statusCode": 400, "body": "No instance_id"}

    # Decision logic
    if cpu < 5:
        ec2.stop_instances(InstanceIds=[instance_id])
        action = "stopped"
    elif cpu > 80:
        action = "scale_up_needed"
    else:
        action = "no_action"

    return {
        "statusCode": 200,
        "body": json.dumps({
            "instance": instance_id,
            "action": action
        })
    }