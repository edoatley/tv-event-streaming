import json
import boto3
import os
import uuid

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
lambda_client = boto3.client('lambda')

# --- Configuration ---
PROGRAMMES_TABLE_NAME = os.environ.get('PROGRAMMES_TABLE_NAME', 'UKTVProgrammes')

# Lambda function ARNs from environment variables (set by CloudFormation)
LAMBDA_FUNCTIONS = {
    "reference_data_refresh": os.environ.get('REFERENCE_DATA_LAMBDA_ARN'),
    "title_data_refresh": os.environ.get('TITLE_DATA_REFRESH_LAMBDA_ARN'),
    "title_enrichment": os.environ.get('TITLE_ENRICHMENT_LAMBDA_ARN')
}

# --- Helper Functions ---

def get_dynamodb_summary():
    """
    Retrieves summary information for DynamoDB tables.
    """
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
        error_message = f"DynamoDB table '{PROGRAMMES_TABLE_NAME}' not found."
        print(f"Error: {error_message}")
        return {"message": error_message, "tables": []}, 404
    except Exception as e:
        error_message = f"Error retrieving DynamoDB summary: {str(e)}"
        print(f"Error: {error_message}")
        return {"message": error_message, "tables": []}, 500

def trigger_lambda_function(function_arn, payload=None):
    """
    Triggers another Lambda function asynchronously using its ARN and returns a job ID.
    """
    job_id = str(uuid.uuid4())
    
    if not function_arn:
        error_message = "Lambda function ARN is not configured."
        print(f"Error: {error_message}")
        return {"message": error_message}, 500
        
    try:
        if payload is None:
            payload = {}
        
        payload['job_id'] = job_id

        lambda_client.invoke(
            FunctionName=function_arn,
            InvocationType='Event',  # Asynchronous invocation
            Payload=json.dumps(payload)
        )
        print(f"Successfully invoked Lambda function: {function_arn} with job ID: {job_id}")
        
        return {"message": f"Lambda function '{function_arn}' initiated.", "job_id": job_id}, 202
    except lambda_client.exceptions.ResourceNotFoundException:
        error_message = f"Lambda function with ARN '{function_arn}' not found."
        print(f"Error: {error_message}")
        return {"message": error_message}, 404
    except Exception as e:
        error_message = f"Error invoking Lambda function {function_arn}: {str(e)}"
        print(f"Error: {error_message}")
        return {"message": error_message}, 500

# --- Main Handler ---

def get_records_that_are_not_enriched():
    pass



def lambda_handler(event, context):
    """
    Main handler for the admin Lambda function.
    Routes requests based on HTTP method and path.
    """
    print(f"Received event: {json.dumps(event)}")

    http_method = event.get('httpMethod')
    path = event.get('path')
    
    response_body = {"message": "Not Found"}
    status_code = 404
    
    # Parse the request body if it exists
    body = {}
    if event.get('body'):
        try:
            body = json.loads(event['body'])
        except json.JSONDecodeError:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({"message": "Invalid JSON in request body"})
            }

    if http_method == 'POST':
        if path == '/admin/reference/refresh':
            body = {"refresh_sources": "Y", "refresh_genres": "Y", "regions": "GB"}
            response_body, status_code = trigger_lambda_function(LAMBDA_FUNCTIONS["reference_data_refresh"], payload=body)
        elif path == '/admin/titles/refresh':
            response_body, status_code = trigger_lambda_function(LAMBDA_FUNCTIONS["title_data_refresh"], payload=body)
        elif path == '/admin/titles/enrich':
            # body = get_records_that_are_not_enriched()
            response_body, status_code = trigger_lambda_function(LAMBDA_FUNCTIONS["title_enrichment"], payload=body)
        else:
            response_body = {"message": f"POST request to unknown path: {path}"}
            status_code = 404
            
    elif http_method == 'GET':
        if path == '/admin/dynamodb/summary':
            response_body, status_code = get_dynamodb_summary()
        else:
            response_body = {"message": f"GET request to unknown path: {path}"}
            status_code = 404
            
    else:
        response_body = {"message": f"Unsupported HTTP method: {http_method}"}
        status_code = 405

    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*' # Adjust CORS as needed
        },
        'body': json.dumps(response_body)
    }
