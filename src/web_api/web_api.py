import json
import logging
import os
import boto3
from datetime import datetime, timedelta
from botocore.exceptions import ClientError
from decimal import Decimal

# Configure logger
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

# --- Environment Variables & Boto3 Clients ---
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
AWS_ENDPOINT_URL = os.environ.get('AWS_ENDPOINT_URL')

# Constants
TITLE_PREFIX = 'title:'
USER_PREF_PREFIX = 'userpref:'
SOURCE_PREFIX = 'source:'
GENRE_PREFIX = 'genre:'

table = None
try:
    if not DYNAMODB_TABLE_NAME:
        raise EnvironmentError("DYNAMODB_TABLE_NAME environment variable must be set.")

    boto3_kwargs = {'endpoint_url': AWS_ENDPOINT_URL} if AWS_ENDPOINT_URL else {}
    dynamodb_resource = boto3.resource('dynamodb', **boto3_kwargs)
    table = dynamodb_resource.Table(DYNAMODB_TABLE_NAME)
    logger.info(f"Successfully initialized DynamoDB table client for: {DYNAMODB_TABLE_NAME}")
except Exception as e:
    logger.error(f"Error during AWS client initialization: {e}", exc_info=True)
    raise

def build_response(status_code, body):
    """Build a standardized API Gateway response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,Authorization',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
        },
        'body': json.dumps(body, default=str)
    }


def get_ref_data(prefix:str):
    """Get all sources from DynamoDB."""
    logger.info(f"Fetching all {prefix}.")
    try:
        response = table.scan(
            FilterExpression='begins_with(PK, :prefix)',

            ExpressionAttributeValues={
                ':prefix': prefix
            },
            ProjectionExpression='PK, SK'
        )
        
        ref_data = []
        for item in response.get('Items', []):
            pk_parts = item.get('PK', '').split(':')
            if len(pk_parts) == 2:
                id = pk_parts[1] # Get the ID part after prefix
                name = item.get('SK', 'Unknown') # Get name from SK
                ref_data.append({"id": id, "name": name})
        
        logger.info(f"Found {len(ref_data)} sources.")
        return ref_data
    except ClientError as e:
        logger.error(f"DynamoDB error getting ref_data: {e}", exc_info=True)
        return []

def get_user_preferences(user_id):
    """Get user preferences from DynamoDB."""
    try:
        pk = f"{USER_PREF_PREFIX}{user_id}"
        response = table.query(
            KeyConditionExpression='PK = :pk',
            ExpressionAttributeValues={':pk': pk}
        )
        
        preferences = {"sources": [], "genres": []}
        for item in response.get('Items', []):
            sk = item.get('SK', '')
            if sk.startswith('source:'):
                pref_id = sk.split(':', 1)[1]
                preferences["sources"].append(pref_id)
            elif sk.startswith('genre:'):
                pref_id = sk.split(':', 1)[1]
                preferences["genres"].append(pref_id)
        
        return preferences
    except ClientError as e:
        logger.error(f"DynamoDB error getting preferences for user {user_id}: {e}", exc_info=True)
        return None

def update_user_preferences(user_id, preferences_data):
    """
    Update user preferences in DynamoDB by calculating the delta of changes.
    This is more efficient and avoids errors from deleting and re-adding the same
    item in a single batch operation.
    """
    try:
        existing_prefs = get_user_preferences(user_id)
        if existing_prefs is None: # Error occurred in get_user_preferences
            return False

        # Use sets for efficient comparison
        existing_sources = set(existing_prefs.get('sources', []))
        existing_genres = set(existing_prefs.get('genres', []))
        new_sources = set(preferences_data.get('sources', []))
        new_genres = set(preferences_data.get('genres', []))

        sources_to_add = new_sources - existing_sources
        sources_to_delete = existing_sources - new_sources
        genres_to_add = new_genres - existing_genres
        genres_to_delete = existing_genres - new_genres

        # Check if there's anything to do
        if not any([sources_to_add, sources_to_delete, genres_to_add, genres_to_delete]):
            logger.info(f"No preference changes for user {user_id}. Nothing to update.")
            return True

        with table.batch_writer() as batch:
            # Add new preferences
            for source_id in sources_to_add:
                batch.put_item(Item={'PK': f'{USER_PREF_PREFIX}{user_id}', 'SK': f'{SOURCE_PREFIX}{source_id}'})
            for genre_id in genres_to_add:
                batch.put_item(Item={'PK': f'{USER_PREF_PREFIX}{user_id}', 'SK': f'{GENRE_PREFIX}{genre_id}'})
            
            # Delete old preferences
            for source_id in sources_to_delete:
                batch.delete_item(Key={'PK': f'{USER_PREF_PREFIX}{user_id}', 'SK': f'{SOURCE_PREFIX}{source_id}'})
            for genre_id in genres_to_delete:
                batch.delete_item(Key={'PK': f'{USER_PREF_PREFIX}{user_id}', 'SK': f'{GENRE_PREFIX}{genre_id}'})
        
        logger.info(f"Successfully updated preferences for user {user_id}")
        return True
    except ClientError as e:
        logger.error(f"DynamoDB error updating preferences for user {user_id}: {e}", exc_info=True)
        return False

def _get_titles_from_dynamo_optimized(user_id, filter_func=None):
    """
    Internal helper to get titles based on user preferences, with an optional filter.
    This version is optimized to avoid N+1 queries by using BatchGetItem.
    """
    try:
        preferences = get_user_preferences(user_id)
        if not preferences or not (preferences.get('sources') and preferences.get('genres')):
            logger.info(f"User {user_id} has no preferences or is missing sources/genres. Returning empty list.")
            return []

        # Step 1: Collect all unique title IDs from the index
        title_ids_to_fetch = set()
        for source_id in preferences.get('sources', []):
            for genre_id in preferences.get('genres', []):
                index_pk = f"source:{source_id}:genre:{genre_id}"
                response = table.query(
                    KeyConditionExpression='PK = :pk',
                    ExpressionAttributeValues={':pk': index_pk},
                    ProjectionExpression='SK' # Only need the title ID
                )
                for item in response.get('Items', []):
                    title_id = item.get('SK', '').split(':', 1)[1]
                    title_ids_to_fetch.add(title_id)
        
        if not title_ids_to_fetch:
            logger.warning(f"No title IDs found for user {user_id}'s preferences. This may indicate the ingestion process has not run for the selected source/genre combinations.")
            return []

        # Step 2: Fetch all title records in batches
        keys_to_get = [{'PK': f"{TITLE_PREFIX}{title_id}", 'SK': 'record'} for title_id in title_ids_to_fetch]
        
        all_items = []
        # batch_get_item has a limit of 100 keys per request. We must chunk the requests.
        for i in range(0, len(keys_to_get), 100):
            chunk = keys_to_get[i:i + 100]
            response = dynamodb_resource.batch_get_item(
                RequestItems={
                    DYNAMODB_TABLE_NAME: {
                        'Keys': chunk,
                        'ConsistentRead': False # Cheaper and faster
                    }
                }
            )
            # A production-ready implementation should also handle 'UnprocessedKeys' from the response.
            all_items.extend(response.get('Responses', {}).get(DYNAMODB_TABLE_NAME, []))

        # Step 3: Process the fetched titles
        titles = []
        for item in all_items:
            title_data = item.get('data', {})
            
            # Apply the filter function if it exists
            if filter_func and not filter_func(title_data):
                continue

            # Add a check for essential data. If a title is not enriched with a poster
            # and plot, it's better to not show it than to show an empty card.
            if not title_data.get('poster') or not title_data.get('plot_overview'):
                logger.debug(f"Skipping title {item.get('PK')} because it is missing poster or plot.")
                continue

            title_id = item.get('PK').split(':', 1)[1]
            titles.append({
                'id': title_id,
                'title': title_data.get('title', 'Unknown'),
                'plot_overview': title_data.get('plot_overview', 'No description available'),
                'poster': title_data.get('poster', ''),
                'user_rating': float(title_data.get('user_rating', 0)) if title_data.get('user_rating') else 0,
                'source_ids': title_data.get('source_ids', []),
                'genre_ids': title_data.get('genre_ids', [])
            })
            
        return titles
    except ClientError as e:
        logger.error(f"DynamoDB error getting titles for user {user_id}: {e}", exc_info=True)
        return []

def get_titles_by_preferences(user_id):
    """Get titles that match the user's preferences."""
    return _get_titles_from_dynamo_optimized(user_id)

def get_recommendations(user_id):
    """Get new recommendations for the user (rating > 7)."""
    def is_recommendation(title_data):
        user_rating = title_data.get('user_rating', 0)
        return user_rating and float(user_rating) > 7

    return _get_titles_from_dynamo_optimized(user_id, filter_func=is_recommendation)

def lambda_handler(event, context):
    """Handle API Gateway requests for the web API."""
    logger.info(f"Received event: {json.dumps(event)}")

    http_method = event.get('httpMethod')
    path = event.get('path')
    
    # Handle preflight OPTIONS request for CORS
    if http_method == 'OPTIONS':
        return build_response(200, {})
    
    # --- Public endpoints (no authentication required) ---
    if http_method == 'GET':
        if path == '/sources':
            return build_response(200, get_ref_data(SOURCE_PREFIX))
        if path == '/genres':
            return build_response(200, get_ref_data(GENRE_PREFIX))

    # --- Protected endpoints (authentication required) ---
    # For protected endpoints, the user's identity is required to fetch or modify
    # user-specific data (e.g., preferences). The identity is provided by the
    # API Gateway's Cognito Authorizer, which validates the JWT (ID Token) sent
    # in the 'Authorization' header. The 'sub' claim from the token, which is a
    # unique identifier for the user, is passed to the Lambda in the event context.
    try:
        user_id = event.get('requestContext', {}).get('authorizer', {}).get('claims', {}).get('sub')
        if not user_id:
            logger.warning(
                "User ID not found in authorizer claims. This indicates a misconfiguration or a call that bypassed the authorizer."
            )
            return build_response(401, {"error": "Unauthorized"})
    except Exception:
        logger.error("Could not parse user ID from event.", exc_info=True)
        return build_response(400, {"error": "Bad request format"})

    if http_method == 'GET':
        if path == '/titles':
            return build_response(200, get_titles_by_preferences(user_id))
        if path == '/recommendations':
            return build_response(200, get_recommendations(user_id))
        if path == '/preferences':
            return build_response(200, get_user_preferences(user_id))

    if http_method == 'PUT':
        if path == '/preferences':
            try:
                body = json.loads(event.get('body', '{}'))
                if update_user_preferences(user_id, body):
                    return build_response(200, {"message": "Preferences updated successfully"})
                else:
                    return build_response(500, {"error": "Failed to update preferences"})
            except json.JSONDecodeError:
                return build_response(400, {"error": "Invalid JSON in request body"})

    return build_response(404, {"error": f"Path not found or method not allowed: {http_method} {path}"})
