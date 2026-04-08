import boto3
from datetime import datetime, timedelta

# Clients
ec2 = boto3.client('ec2', region_name='us-east-1')
cloudwatch = boto3.client('cloudwatch', region_name='us-east-1')

# Identify idle EC2
def lambda_handler(event, context):
    # 7 days ago
    end = datetime.utcnow()
    start = end - timedelta(days=7)

    # List all EC2 instances
    instances = ec2.describe_instances(Filters=[
        {'Name': 'instance-state-name', 'Values': ['running']}
    ])['Reservations']

    for res in instances:
        for i in res['Instances']:
            instance_id = i['InstanceId']
            
            # Get CPU Utilization metrics
            metrics = cloudwatch.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='CPUUtilization',
                Dimensions=[{'Name':'InstanceId','Value':instance_id}],
                StartTime=start,
                EndTime=end,
                Period=3600*24,  # daily
                Statistics=['Average']
            )
            avg_cpu = sum([d['Average'] for d in metrics['Datapoints']]) / len(metrics['Datapoints']) if metrics['Datapoints'] else 0

            # Stop instance if CPU < 5%
            if avg_cpu < 5:
                print(f"Stopping idle instance {instance_id}, CPU={avg_cpu}%")
                ec2.stop_instances(InstanceIds=[instance_id])