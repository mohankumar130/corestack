import boto3
from datetime import datetime, timezone
import argparse

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Delete AWS EC2 snapshots older than a specified date with a specific tag.')
parser.add_argument('cutoff_date', type=str, help='The cutoff date in the format YYYY-MM-DDTHH:MM:SSZ')
parser.add_argument('filter_tag_key', type=str, help='The tag key to filter snapshots')
parser.add_argument('filter_tag_value', type=str, help='The tag value to filter snapshots')
parser.add_argument('--region', type=str, default='us-east-1', help='The AWS region to use (default: us-east-1)')

args = parser.parse_args()

# Convert cutoff_date to timezone-aware datetime object
try:
    cutoff_date = datetime.strptime(args.cutoff_date, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
except ValueError:
    print("Error: Invalid date format. Please use YYYY-MM-DDTHH:MM:SSZ")
    exit(1)

filter_tag_key = args.filter_tag_key
filter_tag_value = args.filter_tag_value

# Initialize EC2 client
ec2 = boto3.client('ec2', region_name=args.region)

print(f"Fetching snapshots older than {cutoff_date} with tag {filter_tag_key}={filter_tag_value}...")

# Fetch snapshots based on the tag filter
try:
    response = ec2.describe_snapshots(
        Filters=[{'Name': f'tag:{filter_tag_key}', 'Values': [filter_tag_value]}]
    )
    snapshots = response.get('Snapshots', [])
except Exception as e:
    print(f"Error fetching snapshots: {e}")
    exit(1)

# Filter snapshots older than the cutoff date
snapshot_ids = [snap['SnapshotId'] for snap in snapshots if snap.get('StartTime', datetime.max).replace(tzinfo=timezone.utc) < cutoff_date]

if not snapshot_ids:
    print("No snapshots found to delete.")
    exit(0)

# Delete old snapshots
for snapshot_id in snapshot_ids:
    print(f"Attempting to delete snapshot: {snapshot_id}")
    try:
        ec2.delete_snapshot(SnapshotId=snapshot_id)
        print(f"Successfully deleted snapshot: {snapshot_id}")
    except Exception as e:
        print(f"Failed to delete snapshot: {snapshot_id}. Error: {e}")
