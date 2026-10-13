"""Daily idle-instance cleanup.

Finds running EC2 instances that have opted in with the tag <AUTO_STOP_TAG>=true
and whose average CPU over the lookback window is below the threshold, then
stops them (or only reports them when DRY_RUN is true). The number of idle and
stopped instances is published to CloudWatch under the FinOps namespace.
"""

import json
import os
from datetime import datetime, timedelta, timezone

import boto3

ec2 = boto3.client("ec2")
cloudwatch = boto3.client("cloudwatch")

CPU_THRESHOLD = float(os.environ.get("CPU_THRESHOLD", "5"))
LOOKBACK_DAYS = int(os.environ.get("LOOKBACK_DAYS", "7"))
AUTO_STOP_TAG = os.environ.get("AUTO_STOP_TAG", "AutoStop")
DRY_RUN = os.environ.get("DRY_RUN", "true").lower() == "true"


def lambda_handler(event, context):
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=LOOKBACK_DAYS)

    idle = []
    for instance_id in opted_in_running_instances():
        avg_cpu = average_cpu(instance_id, start, end)
        if avg_cpu is None:
            print(f"{instance_id}: no CPU data yet, skipping")
            continue
        if avg_cpu < CPU_THRESHOLD:
            idle.append({"instance_id": instance_id, "avg_cpu": round(avg_cpu, 2)})

    stopped = []
    if idle and not DRY_RUN:
        ids = [i["instance_id"] for i in idle]
        ec2.stop_instances(InstanceIds=ids)
        stopped = ids

    cloudwatch.put_metric_data(
        Namespace="FinOps",
        MetricData=[
            {"MetricName": "IdleInstancesFound", "Value": len(idle), "Unit": "Count"},
            {"MetricName": "IdleInstancesStopped", "Value": len(stopped), "Unit": "Count"},
        ],
    )

    result = {"dry_run": DRY_RUN, "idle": idle, "stopped": stopped}
    print(json.dumps(result))
    return result


def opted_in_running_instances():
    paginator = ec2.get_paginator("describe_instances")
    pages = paginator.paginate(Filters=[
        {"Name": "instance-state-name", "Values": ["running"]},
        {"Name": f"tag:{AUTO_STOP_TAG}", "Values": ["true", "True"]},
    ])
    for page in pages:
        for reservation in page["Reservations"]:
            for instance in reservation["Instances"]:
                yield instance["InstanceId"]


def average_cpu(instance_id, start, end):
    datapoints = cloudwatch.get_metric_statistics(
        Namespace="AWS/EC2",
        MetricName="CPUUtilization",
        Dimensions=[{"Name": "InstanceId", "Value": instance_id}],
        StartTime=start,
        EndTime=end,
        Period=86400,  # daily averages
        Statistics=["Average"],
    )["Datapoints"]
    if not datapoints:
        return None
    return sum(d["Average"] for d in datapoints) / len(datapoints)
