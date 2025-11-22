import json
import boto3
import os
import uuid
from datetime import datetime, timedelta

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
lambda_client = boto3.client('lambda')
cloudwatch = boto3.client('cloudwatch')
logs_client = boto3.client('logs')

# --- Configuration ---
PROGRAMMES_TABLE_NAME = os.environ.get('PROGRAMMES_TABLE_NAME', 'UKTVProgrammes')

# Lambda function ARNs from environment variables
# Map friendly names to the environment variable that holds the ARN
LAMBDA_CONFIG = {
    "Reference Data": os.environ.get('REFERENCE_DATA_LAMBDA_ARN'),
    "Title Ingestion": os.environ.get('TITLE_DATA_REFRESH_LAMBDA_ARN'),
    "Title Enrichment": os.environ.get('TITLE_ENRICHMENT_LAMBDA_ARN'),
    "User Preferences": os.environ.get('USER_PREFS_LAMBDA_ARN'),
    "Web API": os.environ.get('WEB_API_LAMBDA_ARN')
}

# --- Helper Functions ---

def get_dynamodb_summary():
    """Retrieves summary information for DynamoDB tables."""
    summary = {"tables": []}
    try:
        table_description = dynamodb.meta.client.describe_table(TableName=PROGRAMMES_TABLE_NAME)
        table_info = table_description['Table']
        
        item_count = table_info.get('ItemCount', 0)
        table_size_bytes = table_info.get('TableSizeBytes', 0)

        summary["tables"].append({
            "name": PROGRAMMES_TABLE_NAME,
            "item_count": item_count,
            "size_bytes": table_size_bytes
        })
        summary["message"] = "DynamoDB data summary retrieved successfully."
        return summary, 200
    except dynamodb.meta.client.exceptions.ResourceNotFoundException:
        return {"message": f"DynamoDB table '{PROGRAMMES_TABLE_NAME}' not found.", "tables": []}, 404
    except Exception as e:
        print(f"Error retrieving DynamoDB summary: {str(e)}")
        return {"message": str(e), "tables": []}, 500

def trigger_lambda_function(function_arn, payload=None):
    """Triggers another Lambda function asynchronously."""
    job_id = str(uuid.uuid4())
    
    if not function_arn:
        return {"message": "Lambda function ARN is not configured."}, 500
        
    try:
        if payload is None: payload = {}
        payload['job_id'] = job_id

        lambda_client.invoke(
            FunctionName=function_arn,
            InvocationType='Event',
            Payload=json.dumps(payload)
        )
        return {"message": f"Lambda function initiated.", "job_id": job_id}, 202
    except Exception as e:
        print(f"Error invoking Lambda {function_arn}: {str(e)}")
        return {"message": str(e)}, 500

def get_lambda_summaries():
    """Fetches invocation and error counts for the last hour for all configured Lambdas."""
    summaries = []
    
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)

    for name, arn in LAMBDA_CONFIG.items():
        if not arn:
            continue

        function_name = arn.split(':')[-1]
        
        try:
            # Fetch Invocations and Errors
            response = cloudwatch.get_metric_data(
                MetricDataQueries=[
                    {
                        'Id': 'invocations',
                        'MetricStat': {
                            'Metric': {
                                'Namespace': 'AWS/Lambda',
                                'MetricName': 'Invocations',
                                'Dimensions': [{'Name': 'FunctionName', 'Value': function_name}]
                            },
                            'Period': 3600,
                            'Stat': 'Sum',
                        },
                        'ReturnData': True,
                    },
                    {
                        'Id': 'errors',
                        'MetricStat': {
                            'Metric': {
                                'Namespace': 'AWS/Lambda',
                                'MetricName': 'Errors',
                                'Dimensions': [{'Name': 'FunctionName', 'Value': function_name}]
                            },
                            'Period': 3600,
                            'Stat': 'Sum',
                        },
                        'ReturnData': True,
                    }
                ],
                StartTime=start_time,
                EndTime=end_time
            )

            invocations = 0
            errors = 0

            if response['MetricDataResults'][0]['Values']:
                invocations = int(response['MetricDataResults'][0]['Values'][0])
            
            if response['MetricDataResults'][1]['Values']:
                errors = int(response['MetricDataResults'][1]['Values'][0])

            success_count = max(0, invocations - errors)
            
            summaries.append({
                "name": name,
                "function_name": function_name,
                "arn": arn,
                "invocations_1h": invocations,
                "errors_1h": errors,
                "success_count_1h": success_count
            })

        except Exception as e:
            print(f"Error fetching metrics for {function_name}: {str(e)}")
            # Add with zero values/error state rather than failing the whole request
            summaries.append({
                "name": name,
                "function_name": function_name,
                "arn": arn,
                "error": str(e)
            })

    return {"lambdas": summaries}, 200

def get_lambda_logs(body):
    """Fetches the most recent log stream for a specific Lambda ARN."""
    function_arn = body.get('function_arn')
    if not function_arn:
        return {"message": "function_arn is required"}, 400

    # Security check: ensure the requested ARN is one of our managed ones
    if function_arn not in LAMBDA_CONFIG.values():
        return {"message": "Unauthorized access to function logs"}, 403

    function_name = function_arn.split(':')[-1]
    log_group_name = f"/aws/lambda/{function_name}"

    try:
        # 1. Get the latest log stream
        streams_response = logs_client.describe_log_streams(
            logGroupName=log_group_name,
            orderBy='LastEventTime',
            descending=True,
            limit=1
        )

        if not streams_response.get('logStreams'):
            return {"message": "No log streams found", "events": []}, 200

        stream_name = streams_response['logStreams'][0]['logStreamName']

        # 2. Get log events
        events_response = logs_client.get_log_events(
            logGroupName=log_group_name,
            logStreamName=stream_name,
            limit=20,
            startFromHead=False 
        )

        formatted_events = []
        for event in events_response.get('events', []):
            formatted_events.append({
                "timestamp": event['timestamp'],
                "message": event['message']
            })

        return {
            "log_group": log_group_name,
            "stream_name": stream_name,
            "events": formatted_events
        }, 200

    except logs_client.exceptions.ResourceNotFoundException:
        return {"message": "Log group not found (function may not have run yet)", "events": []}, 200
    except Exception as e:
        print(f"Error fetching logs for {function_name}: {str(e)}")
        return {"message": f"Error fetching logs: {str(e)}"}, 500

# --- Main Handler ---

def lambda_handler(event, context):
    """Main handler for the admin Lambda function."""
    print(f"Received event: {json.dumps(event)}")

    http_method = event.get('httpMethod')
    path = event.get('path')
    
    # Parse body
    body = {}
    if event.get('body'):
        try:
            body = json.loads(event['body'])
        except json.JSONDecodeError:
            return {'statusCode': 400, 'body': json.dumps({"message": "Invalid JSON"})}

    response_body = {"message": "Not Found"}
    status_code = 404

    if http_method == 'GET':
        if path == '/admin/dynamodb/summary':
            response_body, status_code = get_dynamodb_summary()
        elif path == '/admin/system/lambdas':
            response_body, status_code = get_lambda_summaries()
            
    elif http_method == 'POST':
        if path == '/admin/reference/refresh':
            body = {"refresh_sources": "Y", "refresh_genres": "Y", "regions": "GB"}
            response_body, status_code = trigger_lambda_function(LAMBDA_CONFIG["Reference Data"], payload=body)
        elif path == '/admin/titles/refresh':
            response_body, status_code = trigger_lambda_function(LAMBDA_CONFIG["Title Ingestion"], payload=body)
        elif path == '/admin/titles/enrich':
            response_body, status_code = trigger_lambda_function(LAMBDA_CONFIG["Title Enrichment"], payload=body)
        elif path == '/admin/system/lambdas/logs':
            response_body, status_code = get_lambda_logs(body)

    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response_body)
    }