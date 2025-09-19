import json
import base64
import logging
import os
import boto3
from botocore.exceptions import ClientError

# Configure logger
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

# --- Environment Variables & Boto3 Clients ---
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')
AWS_ENDPOINT_URL = os.environ.get('AWS_ENDPOINT_URL')
TITLE_PREFIX = 'title:'

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

def lambda_handler(event, context):
    """
    Consumes title recommendation events from a Kinesis stream and logs them.
    """
    logger.info(f"Received {len(event.get('Records', []))} records from Kinesis.")

    records_to_save = []
    for record in event.get('Records', []):
        try:
            # Kinesis data is base64 encoded
            payload_bytes = base64.b64decode(record.get('kinesis', {}).get('data'))
            event_data = json.loads(payload_bytes.decode('utf-8'))
            title_payload = event_data.get('payload')

            if title_payload and 'id' in title_payload:
                records_to_save.append(title_payload)
                logger.info(f"Queued title for saving: {title_payload.get('title')} (ID: {title_payload.get('id')})")
            else:
                logger.warning(f"Skipping record with missing payload or ID: {event_data}")

        except (TypeError, json.JSONDecodeError, UnicodeDecodeError) as e:
            logger.error(f"Failed to decode or parse Kinesis record data: {e}")
            # Continue to the next record without failing the whole batch
            continue

    if records_to_save:
        try:
            processed_keys = set() # Use a set to track keys we've already added to the batch
            with table.batch_writer() as batch:
                for title_payload in records_to_save:
                    # --- De-duplicate and write the canonical record ---
                    canonical_pk = f"{TITLE_PREFIX}{title_payload['id']}"
                    canonical_sk = 'record'
                    if (canonical_pk, canonical_sk) not in processed_keys:
                        batch.put_item(Item={
                            'PK': canonical_pk,
                            'SK': canonical_sk,
                            'data': title_payload
                        })
                        processed_keys.add((canonical_pk, canonical_sk))
                    # --- De-duplicate and write the inverted index records ---
                    #    They contain no mutable data, so enrichment is simple.
                    source_ids = title_payload.get('source_ids', [])
                    genre_ids = title_payload.get('genre_ids', [])

                    if not source_ids or not genre_ids:
                        # This warning is expected if the upstream payload is incomplete
                        continue

                    for source_id in source_ids:
                        for genre_id in genre_ids:
                            index_pk = f"source:{source_id}:genre:{genre_id}"
                            index_sk = f"title:{title_payload['id']}"
                            if (index_pk, index_sk) not in processed_keys:
                                # This record enables the 'recommendations' query pattern
                                batch.put_item(Item={
                                    'PK': index_pk,
                                    'SK': index_sk
                                })
                                processed_keys.add((index_pk, index_sk))

            logger.info(f"Successfully processed {len(records_to_save)} titles for DynamoDB.")
        except ClientError as e:
            logger.error(f"Failed to save titles to DynamoDB: {e}", exc_info=True)
            raise

    return {
        'message': f"Successfully processed {len(event.get('Records', []))} records."
    }