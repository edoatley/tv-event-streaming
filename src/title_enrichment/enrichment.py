# src/title_enrichment/enrichment.py
import os
import boto3
import json
import requests
from decimal import Decimal
import logging

# Configure logger
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

# --- Environment Variables ---
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
WATCHMODE_HOSTNAME = os.environ.get('WATCHMODE_HOSTNAME')
WATCHMODE_API_KEY_SECRET_ARN = os.environ.get('WATCHMODE_API_KEY_SECRET_ARN')
AWS_ENDPOINT_URL = os.environ.get('AWS_ENDPOINT_URL') # Check for LocalStack endpoint

# --- Global Clients & Cache ---
_cached_api_key = None
table = None
kinesis_client = None
secrets_manager_client = None

# --- Centralized Initialization Block ---
try:

    # Configure boto3 for LocalStack if endpoint is provided
    boto3_kwargs = {'endpoint_url': AWS_ENDPOINT_URL} if AWS_ENDPOINT_URL else {}
    if AWS_ENDPOINT_URL:
        logger.info(f"Using LocalStack endpoint for DynamoDB: {AWS_ENDPOINT_URL}")

    # Initialise DynamoDB
    if not DYNAMODB_TABLE_NAME:
        raise EnvironmentError("DYNAMODB_TABLE_NAME environment variable must be set.")
    dynamodb_resource = boto3.resource('dynamodb', **boto3_kwargs)
    table = dynamodb_resource.Table(DYNAMODB_TABLE_NAME)
    logger.info(f"Successfully initialized DynamoDB table client for: {DYNAMODB_TABLE_NAME}")


    # Initialise Secrets Manager
    if WATCHMODE_API_KEY_SECRET_ARN:
        secrets_manager_client = boto3.client('secretsmanager', **boto3_kwargs)
        logger.info("Initialized Secrets Manager client.")

except Exception as e:
    logger.error(f"Error during AWS client initialization: {e}", exc_info=True)
    raise

def get_api_key() -> str:
    """Fetch the WatchMode API key from AWS Secrets Manager, caching it for reuse."""
    global _cached_api_key
    if _cached_api_key:
        return _cached_api_key

    if not WATCHMODE_API_KEY_SECRET_ARN:
        raise ValueError("WATCHMODE_API_KEY_SECRET_ARN environment variable not set.")
    if not secrets_manager_client:
        raise RuntimeError("Secrets Manager client was not initialized. Check environment variables.")

    try:
        secret_value_response = secrets_manager_client.get_secret_value(SecretId=WATCHMODE_API_KEY_SECRET_ARN)
        _cached_api_key = secret_value_response['SecretString']
        return _cached_api_key
    except ClientError as e:
        logger.error(f"Error fetching API key from Secrets Manager: {e}")
        raise

def fetch_title_details(api_key, title_id):
    """Fetches detailed information for a single title."""
    url = f'{WATCHMODE_HOSTNAME}/v1/title/{title_id}/details/'
    params = {"apiKey": api_key, "append_to_response": "sources"}
    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        logger.error(f"Error fetching details for title {title_id}: {e}")
        return None

def lambda_handler(event, context):
    """
    Consumes DynamoDB stream events to enrich title records with more details.
    """
    api_key = get_api_key()

    for record in event.get('Records', []):
        if record.get('eventName') != 'INSERT':
            continue

        new_image = record.get('dynamodb', {}).get('NewImage', {})
        pk = new_image.get('PK', {}).get('S')
        sk = new_image.get('SK', {}).get('S')

        # Only process the canonical records, not the index records
        if not pk or not pk.startswith('title:') or sk != 'record':
            continue

        try:
            title_id = pk.split(':', 1)[1]
            logger.info(f"Enriching title ID: {title_id}")

            details = fetch_title_details(api_key, title_id)
            if not details:
                logger.warning(f"Could not fetch details for title {title_id}. Skipping.")
                continue

            # Convert float to Decimal for DynamoDB, handling None values.
            # It's safer to convert via a string to avoid precision issues.
            user_rating = details.get('user_rating')
            rating_to_save = Decimal(str(user_rating)) if user_rating is not None else Decimal('0')

            # Update the original item with the new details
            table.update_item(
                Key={'PK': pk, 'SK': sk},
                UpdateExpression="SET #data.plot_overview = :plot, #data.poster = :poster, #data.user_rating = :rating",
                ExpressionAttributeNames={
                    '#data': 'data'
                },
                ExpressionAttributeValues={
                    ':plot': details.get('plot_overview', 'N/A'),
                    ':poster': details.get('poster', 'N/A'),
                    ':rating': rating_to_save
                }
            )
            logger.info(f"Successfully enriched title ID: {title_id}")

        except Exception as e:
            logger.error(f"Failed to process record {pk}: {e}", exc_info=True)
            # Continue to next record

    return {'statusCode': 200, 'body': json.dumps({'message': f"Processed {len(event.get('Records', []))} records."})}
