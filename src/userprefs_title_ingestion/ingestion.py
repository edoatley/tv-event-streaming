import json
import os
import boto3
import requests
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key
import logging
from datetime import datetime, timezone

# Configure logger
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

# --- Environment Variables ---
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
KINESIS_STREAM_NAME = os.environ.get('KINESIS_STREAM_NAME')
WATCHMODE_HOSTNAME = os.environ.get('WATCHMODE_HOSTNAME')
WATCHMODE_API_KEY_SECRET_ARN = os.environ.get('WATCHMODE_API_KEY_SECRET_ARN')
AWS_ENDPOINT_URL = os.environ.get('AWS_ENDPOINT_URL') # Check for LocalStack endpoint
API_FETCH_LIMIT = int(os.environ.get('API_FETCH_LIMIT', '20'))
USER_PREF_PREFIX = 'userpref:'

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

    # Initialise Kinesis
    if KINESIS_STREAM_NAME:
        kinesis_client = boto3.client('kinesis', **boto3_kwargs)
        logger.info(f"Initialized Kinesis client for stream {KINESIS_STREAM_NAME}")

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


def get_all_user_preferences() -> dict:
    """Scan DynamoDB to aggregate all unique source and genre preferences across all users."""
    all_sources = set()
    all_genres = set()
    try:
        # Use the high-level resource's scan method.
        # It handles pagination automatically when you check for 'LastEvaluatedKey'.
        response = table.scan(
            FilterExpression=Key('PK').begins_with(USER_PREF_PREFIX)
        )
        items = response.get('Items', [])

        # Manually handle pagination for subsequent pages if the table is large
        while 'LastEvaluatedKey' in response:
            response = table.scan(
                FilterExpression=Key('PK').begins_with(USER_PREF_PREFIX),
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            items.extend(response.get('Items', []))

        for item in items:
            # With the resource API, 'item' is a standard Python dict.
            # No need to unwrap data types like .get('S').
            sk = item.get('SK', '')
            if not sk:
                continue
            try:
                prefix, pref_id = sk.split(':', 1)
                if prefix == 'source':
                    all_sources.add(pref_id)
                elif prefix == 'genre':
                    all_genres.add(pref_id)
            except ValueError:
                logger.warning(f"Skipping malformed SK: {sk}")

        logger.info(f"Found {len(all_sources)} unique sources and {len(all_genres)} unique genres.")
        # Sorting the lists makes the output deterministic and easier to test
        return {"sources": sorted(list(all_sources)), "genres": sorted(list(all_genres))}
    except ClientError as e:
        logger.error(f"Error scanning for user preferences: {e}")
        raise


def fetch_titles(api_key: str, sources: list, genres: list) -> list:
    """Fetch titles from the WatchMode API based on aggregated source and genre preferences."""
    if not sources or not genres:
        logger.info("No sources or genres to fetch titles for.")
        return []

    url = f'{WATCHMODE_HOSTNAME}/v1/list-titles/'
    params = {
        "apiKey": api_key,
        "source_ids": ",".join(sources),
        "genres": ",".join(genres),
        "regions": "GB",
        "limit": API_FETCH_LIMIT

    }
    try:
        response = requests.get(url, params=params, timeout=20)
        response.raise_for_status()
        data = response.json()
        return data.get('titles', [])
    except requests.exceptions.RequestException as e:
        logger.error(f"Error fetching titles from WatchMode: {e}")
        return [] # Return empty list on error to not fail the whole process

def publish_titles_to_kinesis(titles: list, source_ids: list, genre_ids: list):
    """Publish a list of title records to the Kinesis stream in batches."""
    if not titles:
        logger.info("No titles to publish.")
        return

    records = []
    for title in titles:
        title['source_ids'] = source_ids
        title['genre_ids'] = genre_ids

        payload = {
            "header": {
                "publishingComponent": "UserPrefsTitleIngestionFunction",
                "publishTimestamp": datetime.now(timezone.utc).isoformat(),
                "publishCause": "scheduled_user_prefs_ingestion"
            },
            "payload": title
        }
        records.append({
            'Data': json.dumps(payload),
            'PartitionKey': str(title.get('id', 'unknown'))
        })

    # Process records in chunks of 500 (the Kinesis limit)
    for i in range(0, len(records), 500):
        chunk = records[i:i + 500]
        try:
            if chunk:
                kinesis_client.put_records(StreamName=KINESIS_STREAM_NAME, Records=chunk)
                logger.info(f"Successfully published a chunk of {len(chunk)} titles to Kinesis.")
        except ClientError as e:
            logger.error(f"Error publishing a chunk of records to Kinesis: {e}")
            raise

def lambda_handler(event, context):
    """Orchestrate the title ingestion process based on all user preferences.
     This function scans for all user preferences, fetches matching titles from an
     external API, and publishes the results to a Kinesis stream.
     """
    logger.info(f"Starting title ingestion based on all user preferences.")

    try:
        api_key = get_api_key()
        preferences = get_all_user_preferences()

        if preferences.get("sources") and preferences.get("genres"):
            titles = fetch_titles(api_key, preferences["sources"], preferences["genres"])
            publish_titles_to_kinesis(titles, preferences["sources"], preferences["genres"])
        else:
            logger.info("No user preferences found, nothing to ingest.")

        return {'statusCode': 200, 'body': json.dumps({'message': 'Ingestion process completed.'})}
    except Exception as e:
        logger.error(f"An unhandled error occurred: {e}", exc_info=True)
        raise