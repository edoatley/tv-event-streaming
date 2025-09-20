#!/bin/bash
# Script to initialize resources in LocalStack for the event-streaming-app

if [ -z "${WATCHMODE_API_KEY:-}" ]; then
  echo -e "\033[1;31mError: WATCHMODE_API_KEY environment variable is not set.\033[0m" >&2
  echo "Please export your key before running this script." >&2
  exit 1
fi

# Configuration
REGION="eu-west-2"
ENDPOINT_URL="http://localhost:4566"
TABLE_NAME="UKTVProgrammesLocal"
STREAM_NAME="ProgrammeDataStreamLocal"
SECRET_NAME="local/WatchModeApiKey"

# Set environment variables
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION=${REGION}

# AWS CLI command alias
AWS="aws --endpoint-url=${ENDPOINT_URL} --region ${REGION}"

echo ""
echo "--- Creating DynamoDB table: ${TABLE_NAME} ---"
$AWS dynamodb create-table \
    --table-name ${TABLE_NAME} \
    --attribute-definitions AttributeName=PK,AttributeType=S AttributeName=SK,AttributeType=S \
    --key-schema AttributeName=PK,KeyType=HASH AttributeName=SK,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST | jq

echo ""
echo "--- Creating Kinesis stream: ${STREAM_NAME} ---"
$AWS kinesis create-stream \
    --stream-name ${STREAM_NAME} \
    --shard-count 1 | jq

echo ""
echo "--- Creating Secrets Manager secret: ${SECRET_NAME} ---"
$AWS secretsmanager create-secret \
    --name ${SECRET_NAME} \
    --secret-string "${WATCHMODE_API_KEY}" | jq

echo ""
echo "--- Setup complete. ---"