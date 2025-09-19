import json
import os
import boto3
from botocore.exceptions import ClientError
import logging
import decimal

# Configure logger
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

# Environment variables
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
AWS_ENDPOINT_URL = os.environ.get('AWS_ENDPOINT_URL')

# Constants
USER_PREF_PREFIX = 'userpref:'
SOURCE_PREFIX = 'source:'
GENRE_PREFIX = 'genre:'

# Global AWS clients
table = None

# Initialization block
try:
    if not DYNAMODB_TABLE_NAME:
        raise EnvironmentError("DYNAMODB_TABLE_NAME environment variable must be set.")
    boto3_kwargs = {}
    if AWS_ENDPOINT_URL:
        logger.info(f"Using LocalStack endpoint for DynamoDB: {AWS_ENDPOINT_URL}")
        boto3_kwargs['endpoint_url'] = AWS_ENDPOINT_URL

    dynamodb_resource = boto3.resource('dynamodb', **boto3_kwargs)
    table = dynamodb_resource.Table(DYNAMODB_TABLE_NAME)
    logger.info(f"Successfully initialized DynamoDB table client for: {DYNAMODB_TABLE_NAME}")
except (EnvironmentError, ClientError) as e:
    logger.error(f"Initialization error: {e}", exc_info=True)
    raise


class DecimalEncoder(json.JSONEncoder):
    """Custom JSON Encoder to handle DynamoDB's Decimal type."""

    def default(self, o):
        if isinstance(o, decimal.Decimal):
            return int(o) if o % 1 == 0 else float(o)
        return super(DecimalEncoder, self).default(o)


def build_response(status_code, body):
    """Build a standard API Gateway proxy response object."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, cls=DecimalEncoder)
    }


def get_entities(pk_prefix: str):
    """Scan DynamoDB for all entities with a given PK prefix, such as 'source:'."""
    try:
        response = table.scan(
            FilterExpression="begins_with(PK, :pk_prefix)",
            ExpressionAttributeValues={":pk_prefix": pk_prefix}
        )
        items = response.get('Items', [])

        while 'LastEvaluatedKey' in response:
            response = table.scan(
                FilterExpression="begins_with(PK, :pk_prefix)",
                ExpressionAttributeValues={":pk_prefix": pk_prefix},
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            items.extend(response.get('Items', []))

        clean_items = [item.get('data', {}) for item in items]
        return build_response(200, clean_items)

    except ClientError as e:
        logger.error(f"DynamoDB ClientError getting entities: {e}", exc_info=True)
        return build_response(500, {"error": "Could not retrieve data."})
    except Exception as e:
        logger.error(f"Unexpected error getting entities: {e}", exc_info=True)
        return build_response(500, {"error": "An unexpected error occurred."})


def _get_user_preferences_items(user_id: str) -> list:
    """Fetch all raw preference items for a specific user ID from DynamoDB."""
    pk = f"{USER_PREF_PREFIX}{user_id}"
    logger.info(f"Querying for raw preference items with PK: {pk}")
    try:
        response = table.query(KeyConditionExpression=boto3.dynamodb.conditions.Key('PK').eq(pk))
        logger.info(f"Query response: {response}")
        return response.get('Items', [])
    except ClientError as e:
        logger.error(f"DynamoDB error in _get_user_preferences_items for user {user_id}: {e}", exc_info=True)
        raise  # Re-raise the exception to be handled by the calling function


def get_user_preferences(user_id: str):
    """Retrieve and format a user's preferences for sources and genres."""
    logger.info(f"Handling GET /preferences request for user: {user_id}")
    try:
        items = _get_user_preferences_items(user_id)

        preferences = {"sources": [], "genres": []}
        for item in items:
            sk = item.get('SK', '')
            try:
                prefix, pref_id = sk.split(':', 1)
                if prefix == 'source':
                    preferences["sources"].append(pref_id)
                elif prefix == 'genre':
                    preferences["genres"].append(pref_id)
            except ValueError:
                logger.warning(f"Skipping malformed SK in user preferences: {sk}")
                continue

        return build_response(200, preferences)
    except ClientError as e:
        logger.error(f"DynamoDB error getting preferences for user {user_id}: {e}", exc_info=True)
        return build_response(500, {'error': 'Could not retrieve preferences'})


def set_user_preferences(user_id: str, body: dict):
    """Calculate the delta between old and new preferences and update DynamoDB in a batch."""
    try:
        # 1. Get existing preferences internal helper
        existing_items = _get_user_preferences_items(user_id)
        existing_prefs_sk_set = {item['SK'] for item in existing_items}

        # 2. Prepare the new preferences from the request body.
        new_sources = body.get('sources', [])
        new_genres = body.get('genres', [])
        new_prefs_sk_set = {f"source:{s}" for s in new_sources} | {f"genre:{g}" for g in new_genres}

        # 3. Calculate the delta: what to add and what to delete.
        items_to_add = new_prefs_sk_set - existing_prefs_sk_set
        items_to_delete = existing_prefs_sk_set - new_prefs_sk_set

        logger.info(f"Items to add: {items_to_add}")
        logger.info(f"Items to delete: {items_to_delete}")

        # If there's nothing to do, exit early.
        if not items_to_add and not items_to_delete:
            logger.info("No preference changes detected. Exiting.")
            return build_response(204, {})

        # 4. Use the batch_writer to efficiently apply only the changes.
        with table.batch_writer() as batch:
            pk = f"{USER_PREF_PREFIX}{user_id}"
            for sk in items_to_delete:
                logger.info(f"Queueing delete for user {user_id}, item {sk}")
                batch.delete_item(Key={'PK': pk, 'SK': sk})

            for sk in items_to_add:
                logger.info(f"Queueing put for user {user_id}, item {sk}")
                batch.put_item(Item={'PK': pk, 'SK': sk})

    except ClientError as e:
        logger.error(f"DynamoDB error setting preferences for user {user_id}: {e}", exc_info=True)
        return build_response(500, {'error': 'Could not set preferences'})
    except Exception as e:
        logger.error(f"An unexpected error occurred while setting preferences for user {user_id}: {e}", exc_info=True)
        return build_response(500, {'error': 'An unexpected error occurred'})

    return {
        "statusCode": 204,
        "headers": {
            "Access-Control-Allow-Origin": "*",
        }
    }


def lambda_handler(event, context):
    """Handle API Gateway requests for user preferences, sources, and genres.
     This function acts as a router, directing incoming requests to the appropriate
     logic based on the HTTP method and path.
     """
    logger.info(f"Received event: {json.dumps(event)}")

    http_method = event.get('httpMethod')
    path = event.get('path')

    if http_method == 'GET' and path == '/sources':
        return get_entities(SOURCE_PREFIX)

    elif http_method == 'GET' and path == '/genres':
        return get_entities(GENRE_PREFIX)

    elif path == '/preferences':
        try:
            user_id = event.get('requestContext', {}).get('authorizer', {}).get('claims', {}).get('sub')
            if not user_id:
                logger.warning("User ID not found in authorizer claims.")
                return build_response(401, {"error": "Unauthorized"})
        except Exception:
            logger.error("Could not parse user ID from event.", exc_info=True)
            return build_response(400, {"error": "Bad request format"})

        if http_method == 'GET':
            return get_user_preferences(user_id)
        elif http_method == 'PUT':
            try:
                body = json.loads(event.get('body') or '{}')
                return set_user_preferences(user_id, body)
            except json.JSONDecodeError:
                logger.warning("Received invalid JSON in PUT /preferences body")
                return build_response(400, {"error": "Invalid JSON format"})

    return build_response(404, {"error": f"Path not found: {http_method} {path}"})
