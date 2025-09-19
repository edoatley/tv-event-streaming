import requests
import os
import json
import boto3
from botocore.exceptions import ClientError
import logging

# Configure logger
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper()) # Allow log level to be set by env var

# Define constants for DynamoDB keys and prefixes
PK_FIELD = 'PK'
SK_FIELD = 'SK'
DATA_FIELD = 'data'
SOURCE_PREFIX = 'source:'
GENRE_PREFIX = 'genre:'

# Environment variables
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
WATCHMODE_HOSTNAME = os.environ.get('WATCHMODE_HOSTNAME')
WATCHMODE_API_KEY_SECRET_ARN = os.environ.get('WATCHMODE_API_KEY_SECRET_ARN')
AWS_ENDPOINT_URL = os.environ.get('AWS_ENDPOINT_URL') # Check for LocalStack endpoint

# Global AWS clients and fetched API key
dynamodb_resource = None
table = None
secrets_manager_client = None
_cached_watchmode_api_key = None

# Initialization block
try:
    if not DYNAMODB_TABLE_NAME:
        raise EnvironmentError("DYNAMODB_TABLE_NAME environment variable not set.")
    if not WATCHMODE_HOSTNAME:
        raise EnvironmentError("WATCHMODE_HOSTNAME environment variable not set.")
    if not WATCHMODE_API_KEY_SECRET_ARN:
        raise EnvironmentError("WATCHMODE_API_KEY_SECRET_ARN environment variable not set.")

    # Configure boto3 for LocalStack if endpoint is provided
    is_local = os.environ.get("AWS_SAM_LOCAL")
    boto3_kwargs = {}
    if is_local and AWS_ENDPOINT_URL:
        logger.info(f"Using LocalStack endpoint: {AWS_ENDPOINT_URL}")
        boto3_kwargs['endpoint_url'] = AWS_ENDPOINT_URL
    else:
        logger.info(f"Using AWS Default endpoint because {AWS_ENDPOINT_URL=} {is_local=}")

    # Configure AWS resources the lambda requires
    dynamodb_resource = boto3.resource('dynamodb', **boto3_kwargs)
    table = dynamodb_resource.Table(DYNAMODB_TABLE_NAME)
    logger.info(f"Successfully initialized DynamoDB table: {DYNAMODB_TABLE_NAME}")
    secrets_manager_client = boto3.client('secretsmanager', **boto3_kwargs)
    logger.info("Successfully initialized Secrets Manager client.")
except (EnvironmentError, ClientError) as e:
    logger.error(f"Initialization error: {e}", exc_info=True)
    raise


def get_watchmode_api_key_secret() -> str:
    """Fetch the WatchMode API key from AWS Secrets Manager, caching it for reuse."""
    global _cached_watchmode_api_key
    if _cached_watchmode_api_key:
        return _cached_watchmode_api_key

    if not secrets_manager_client:
        raise ValueError("Secrets Manager client was not initialized. Check WATCHMODE_API_KEY_SECRET_ARN.")

    try:
        logger.info(f"Fetching secret: {WATCHMODE_API_KEY_SECRET_ARN}")
        secret_value_response = secrets_manager_client.get_secret_value(
            SecretId=WATCHMODE_API_KEY_SECRET_ARN
        )
        _cached_watchmode_api_key = secret_value_response['SecretString']
        return _cached_watchmode_api_key
    except ClientError as e:
        logger.error(f"Error fetching API key from Secrets Manager: {e}")
        raise


def _fetch_watchmode_data(api_key: str, endpoint: str, params: dict = None) -> list:
    """Make a generic GET request to a specified WatchMode API endpoint."""
    if not WATCHMODE_HOSTNAME:
        logger.error("WATCHMODE_HOSTNAME is not configured.")
        return [] # Or raise

    url = f'{WATCHMODE_HOSTNAME}/v1/{endpoint}/'
    base_params = {"apiKey": api_key}
    if params:
        base_params.update(params)

    try:
        logger.info(f"Fetching data from {url} with params: {params if params else 'N/A'}")
        response = requests.get(url, params=base_params, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        logger.error(f"Error fetching data from {url}: {e}", exc_info=True)
        return []
    except json.JSONDecodeError as e:
        logger.error(f"Error decoding JSON response from {url}: {e}", exc_info=True)
        return []


def get_sources(region: str, api_key: str) -> list:
    """Fetch all streaming sources available from the WatchMode API for a given region."""
    return _fetch_watchmode_data(api_key, "sources", params={"regions": region})


def get_genres(api_key: str) -> list:
    """Fetch all available genres from the WatchMode API."""
    return _fetch_watchmode_data(api_key, "genres")


def _save_items_to_dynamodb(items_list: list, item_type_prefix: str, item_type_name: str) -> bool:
    """Save a list of items (like sources or genres) to DynamoDB using a batch writer."""
    if not table:
        logger.error(f"DynamoDB table not available for saving {item_type_name}s.")
        return False

    if not items_list: # No items to save
        logger.info(f"No {item_type_name} items provided to save.")
        return True # Operation considered successful as there's nothing to do

    try:
        with table.batch_writer() as batch:
            for item in items_list:
                if not isinstance(item, dict) or 'id' not in item or 'name' not in item:
                    logger.warning(f"Skipping invalid {item_type_name}_item: {item}")
                    continue
                item_to_save = {
                    PK_FIELD: f'{item_type_prefix}{item["id"]}',
                    SK_FIELD: item["name"],
                    DATA_FIELD: item
                }
                batch.put_item(Item=item_to_save)
        logger.info(f"Successfully saved {len(items_list)} {item_type_name} items to DynamoDB.")
        return True
    except ClientError as e:
        logger.error(f"DynamoDB batch write error for {item_type_name}s: {e}", exc_info=True)
        return False


def save_sources_to_dynamodb(sources_list: list):
    """Save a list of source objects to DynamoDB."""
    return _save_items_to_dynamodb(sources_list, SOURCE_PREFIX, "source")


def save_genres_to_dynamodb(genres_list: list):
    """Save a list of genre objects to DynamoDB."""
    return _save_items_to_dynamodb(genres_list, GENRE_PREFIX, "genre")



def _process_source_refresh(api_key: str, event: dict) -> tuple[str | None, bool]:
    """Handles the logic for refreshing sources, returning a message and success status."""
    if event.get('refresh_sources', 'N').upper() != 'Y':
        return None, True  # No action requested, operation is successful.

    region = event.get("regions", "GB")
    logger.info(f"Attempting to refresh sources for region: {region}")
    sources_data = get_sources(region, api_key)
    if sources_data and save_sources_to_dynamodb(sources_data):
        return f'Sources refreshed for region {region}', True
    else:
        return f'No sources found or error saving for region {region}', False

def _process_genre_refresh(api_key: str, event: dict) -> tuple[str | None, bool]:
    """Handles the logic for refreshing genres, returning a message and success status."""
    if event.get('refresh_genres', 'N').upper() != 'Y':
        return None, True

    logger.info("Attempting to refresh genres")
    genres_data = get_genres(api_key)
    if genres_data and save_genres_to_dynamodb(genres_data):
        return 'Genres refreshed', True
    else:
        return 'No genres found or error saving', False

def lambda_handler(event, context):
    """Refresh reference data like sources and genres from an external API.
    This function is triggered by an event and fetches data from the WatchMode API,
    then saves it into DynamoDB for application-wide use.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    try:
        api_key = get_watchmode_api_key_secret()
    except Exception as e:
        logger.error(f"Failed to get API key: {e}")
        return {'statusCode': 500, 'body': json.dumps({'error': f'Failed to retrieve API key: {str(e)}'})}

    messages = []
    all_successful = True

    try:
        source_msg, source_success = _process_source_refresh(api_key, event)
        if source_msg: messages.append(source_msg)
        if not source_success: all_successful = False

        genre_msg, genre_success = _process_genre_refresh(api_key, event)
        if genre_msg: messages.append(genre_msg)
        if not genre_success: all_successful = False

    except Exception as e:
        logger.error(f"An unhandled exception occurred during refresh processing: {e}", exc_info=True)
        messages.append("An unexpected server error occurred.")
        return {'statusCode': 500, 'body': json.dumps({'messages': messages, 'success': False})}

    # If no refresh was requested
    if not messages:
        messages.append("No refresh action requested.")

    status_code = 200 if all_successful else 500
    return {'statusCode': status_code, 'body': json.dumps({'messages': messages, 'success': all_successful})}
