#!/bin/bash

# This script fetches the most recent CloudWatch logs for a given Lambda function.
# It's a useful tool for quickly debugging Lambda execution issues.

set -e
set -o pipefail

# --- Configuration ---
PROFILE="streaming"
REGION="eu-west-2"

# --- Helper Functions ---
log() {
    echo "✅ $1"
}

info() {
    echo "   - $1"
}

error() {
    echo "❌ ERROR: $1" >&2
    exit 1
}

# --- Main Script ---

PARTIAL_FUNCTION_NAME=$1
if [ -z "$PARTIAL_FUNCTION_NAME" ]; then
    error "Usage: $0 <partial-lambda-function-name>\nExample: $0 WebApiFunction"
fi

echo "🚀 Fetching logs for Lambda function containing '$PARTIAL_FUNCTION_NAME'..."

# Step 1: Prerequisite check
if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install it to run these tests (e.g., 'brew install jq')."
fi
log "Prerequisite check passed (jq is installed)."

# Step 2: Check AWS session
log "Step 2: Checking AWS SSO session for profile: ${PROFILE}..."
if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
    echo "⚠️ AWS SSO session expired or not found. Please log in."
    aws sso login --profile "${PROFILE}"
fi
log "AWS SSO session is active."

# Step 3: Find the full function name
log "Step 3: Searching for Lambda function..."
FUNCTION_NAME=$(aws lambda list-functions \
  --query "Functions[?contains(FunctionName, \`$PARTIAL_FUNCTION_NAME\`)].FunctionName" \
  --output text --profile "$PROFILE" --region "$REGION")

if [ -z "$FUNCTION_NAME" ]; then
  error "Could not find a Lambda function containing the name '$PARTIAL_FUNCTION_NAME'."
fi

if [ $(echo "$FUNCTION_NAME" | wc -w) -gt 1 ]; then
  error "Found multiple functions matching '$PARTIAL_FUNCTION_NAME'. Please be more specific. Found:\n$FUNCTION_NAME"
fi
log "Found function: $FUNCTION_NAME"

LOG_GROUP_NAME="/aws/lambda/${FUNCTION_NAME}"

# Step 4: Find the most recent log stream
log "Step 4: Finding the most recent log stream in group '$LOG_GROUP_NAME'..."
LATEST_LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP_NAME" \
  --order-by LastEventTime --descending --limit 1 \
  --query "logStreams[0].logStreamName" --output text \
  --profile "$PROFILE" --region "$REGION")

if [ -z "$LATEST_LOG_STREAM" ] || [ "$LATEST_LOG_STREAM" == "None" ]; then
  error "No log streams found for log group '$LOG_GROUP_NAME'."
fi
log "Found stream: $LATEST_LOG_STREAM"

# Step 5: Get and display log events
echo ""
echo "📄 Displaying logs from the most recent stream..."
echo "--------------------------------------------------"
aws logs get-log-events \
  --log-group-name "$LOG_GROUP_NAME" \
  --log-stream-name "$LATEST_LOG_STREAM" \
  --query "events[*].{ts:timestamp, msg:message}" --output json \
  --profile "$PROFILE" --region "$REGION" | \
  jq -r '.[] | "\(.ts | tonumber / 1000 | strftime("%Y-%m-%d %H:%M:%S")) UTC | \(.msg | rtrimstr("\n"))"'

echo "--------------------------------------------------"
echo "🎉 Log fetching complete."