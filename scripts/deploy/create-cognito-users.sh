#!/bin/bash
# Script to invoke the UserCreation Lambda function and save passwords to Secrets Manager
# Usage: ./create-cognito-users.sh <UserPoolId> <UserNames> <AdminUserNames> <StackName> [Region]

set -eou pipefail

# --- Parameters ---
USER_POOL_ID="$1"
USER_NAMES="$2"
ADMIN_USER_NAMES="$3"
STACK_NAME="${4:-tv-event-streaming-gha}"
REGION="${5:-eu-west-2}"

# --- Try to read from config file if parameters not provided ---
CONFIG_FILE="config/users.json"
if [ -z "$USER_NAMES" ] && [ -f "$CONFIG_FILE" ]; then
    echo "Reading user configuration from $CONFIG_FILE..."
    USER_NAMES=$(jq -r '.users[].email' "$CONFIG_FILE" | tr '\n' ',' | sed 's/,$//')
    if [ -z "$ADMIN_USER_NAMES" ]; then
        ADMIN_USER_NAMES=$(jq -r '.users[] | select(.type == "admin") | .email' "$CONFIG_FILE" | tr '\n' ',' | sed 's/,$//')
    fi
    echo "  Loaded users: $USER_NAMES"
    if [ -n "$ADMIN_USER_NAMES" ]; then
        echo "  Admin users: $ADMIN_USER_NAMES"
    fi
fi

# --- Validation ---
if [ -z "$USER_POOL_ID" ] || [ -z "$USER_NAMES" ]; then
    echo "Error: Usage: $0 <UserPoolId> [UserNames] [AdminUserNames] <StackName> [Region]"
    echo "  UserPoolId: The Cognito User Pool ID (required)"
    echo "  UserNames: Comma-separated list of usernames (optional if config/users.json exists)"
    echo "  AdminUserNames: Comma-separated list of admin usernames (optional if config/users.json exists)"
    echo "  StackName: CloudFormation stack name (default: tv-event-streaming-gha)"
    echo "  Region: AWS region (default: eu-west-2)"
    echo ""
    echo "If UserNames is not provided, the script will attempt to read from config/users.json"
    exit 1
fi

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

warn() {
    echo "⚠️  WARNING: $1" >&2
}

# --- Prerequisites Check ---
if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install it (e.g., 'brew install jq')."
fi

# --- Fetch Lambda Function Name from Stack ---
log "Fetching Lambda function name from stack: $STACK_NAME"
STACK_OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs" \
    --output json 2>/dev/null || echo "[]")

if [ "$STACK_OUTPUTS" == "[]" ] || [ -z "$STACK_OUTPUTS" ]; then
    # Try to construct function name from stack name pattern
    FUNCTION_NAME="${STACK_NAME}-UserCreation"
    warn "Could not fetch stack outputs. Using constructed function name: $FUNCTION_NAME"
else
    FUNCTION_NAME=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="UserCreationFunctionName") | .OutputValue')
    
    if [ -z "$FUNCTION_NAME" ] || [ "$FUNCTION_NAME" == "null" ]; then
        # Fallback to constructed name
        FUNCTION_NAME="${STACK_NAME}-UserCreation"
        warn "UserCreationFunctionName not found in stack outputs. Using constructed name: $FUNCTION_NAME"
    fi
fi

log "Using Lambda function: $FUNCTION_NAME"

# --- Prepare Lambda Payload ---
PAYLOAD=$(jq -n \
    --arg userPoolId "$USER_POOL_ID" \
    --arg userNames "$USER_NAMES" \
    --arg adminUserNames "${ADMIN_USER_NAMES:-}" \
    '{
        UserPoolId: $userPoolId,
        UserNames: $userNames,
        AdminUserNames: $adminUserNames
    }')

info "Invoking Lambda function with payload:"
echo "$PAYLOAD" | jq '.'

# --- Invoke Lambda Function ---
log "Invoking Lambda function..."
INVOCATION_RESULT=$(aws lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --payload "$PAYLOAD" \
    --region "$REGION" \
    --cli-binary-format raw-in-base64-out \
    /tmp/lambda-response.json 2>&1)

if [ $? -ne 0 ]; then
    error "Failed to invoke Lambda function. Error: $INVOCATION_RESULT"
fi

# --- Parse Lambda Response ---
RESPONSE_BODY=$(cat /tmp/lambda-response.json)
STATUS_CODE=$(echo "$RESPONSE_BODY" | jq -r '.statusCode // 200')

if [ "$STATUS_CODE" != "200" ] && [ "$STATUS_CODE" != "207" ]; then
    error_msg=$(echo "$RESPONSE_BODY" | jq -r '.body // .errorMessage // "Unknown error"')
    
    # Try to parse error from body if it's a JSON string
    if echo "$error_msg" | jq -e . >/dev/null 2>&1; then
        error_msg=$(echo "$error_msg" | jq -r '.error // .')
    fi
    
    error "Lambda invocation failed with status code $STATUS_CODE: $error_msg"
fi

# Extract response body
if echo "$RESPONSE_BODY" | jq -e '.body' >/dev/null 2>&1; then
    # Response has a body field (stringified JSON)
    RESPONSE_DATA=$(echo "$RESPONSE_BODY" | jq -r '.body')
    if echo "$RESPONSE_DATA" | jq -e . >/dev/null 2>&1; then
        # Body is JSON, parse it
        LAMBDA_RESPONSE=$(echo "$RESPONSE_DATA" | jq .)
    else
        # Body is not JSON, use as-is
        LAMBDA_RESPONSE="$RESPONSE_DATA"
    fi
else
    # Response is the body itself
    LAMBDA_RESPONSE=$(echo "$RESPONSE_BODY" | jq .)
fi

# Extract UserPasswords and Warnings
USER_PASSWORDS=$(echo "$LAMBDA_RESPONSE" | jq -r '.UserPasswords // {}')
WARNINGS=$(echo "$LAMBDA_RESPONSE" | jq -r '.Warnings // []')
FAILED_USERS=$(echo "$LAMBDA_RESPONSE" | jq -r '.FailedUsers // []')

# --- Check for Errors ---
if [ "$STATUS_CODE" == "207" ] || [ "$FAILED_USERS" != "[]" ] && [ "$FAILED_USERS" != "null" ]; then
    warn "Some users failed to create. Failed users: $FAILED_USERS"
fi

if [ "$WARNINGS" != "[]" ] && [ "$WARNINGS" != "null" ]; then
    warn "Warnings during user creation:"
    echo "$WARNINGS" | jq -r '.[]' | while read -r warning; do
        echo "   - $warning"
    done
fi

# --- Fetch and Display Logs on Failure ---
if [ "$STATUS_CODE" != "200" ] && [ "$STATUS_CODE" != "207" ]; then
    log "Fetching CloudWatch logs for debugging..."
    LOG_GROUP_NAME="/aws/lambda/${FUNCTION_NAME}"
    
    # Find the most recent log stream
    LATEST_LOG_STREAM=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP_NAME" \
        --order-by LastEventTime --descending --limit 1 \
        --query "logStreams[0].logStreamName" --output text \
        --region "$REGION" 2>/dev/null || echo "")
    
    if [ -n "$LATEST_LOG_STREAM" ] && [ "$LATEST_LOG_STREAM" != "None" ]; then
        echo ""
        echo "📄 CloudWatch Logs (most recent stream: $LATEST_LOG_STREAM):"
        echo "--------------------------------------------------"
        aws logs get-log-events \
            --log-group-name "$LOG_GROUP_NAME" \
            --log-stream-name "$LATEST_LOG_STREAM" \
            --query "events[*].{ts:timestamp, msg:message}" --output json \
            --region "$REGION" | \
            jq -r '.[] | "\(.ts | tonumber / 1000 | strftime("%Y-%m-%d %H:%M:%S")) UTC | \(.msg | rtrimstr("\n"))"'
        echo "--------------------------------------------------"
    else
        warn "Could not fetch CloudWatch logs. Log group: $LOG_GROUP_NAME"
    fi
    
    error "User creation failed. Check logs above for details."
fi

# --- Save Passwords to Secrets Manager ---
if [ "$USER_PASSWORDS" != "{}" ] && [ "$USER_PASSWORDS" != "null" ]; then
    SECRET_NAME="${STACK_NAME}/UserPasswords"
    log "Saving passwords to Secrets Manager: $SECRET_NAME"
    
    # Check if secret exists
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" >/dev/null 2>&1; then
        info "Secret already exists. Updating..."
        aws secretsmanager update-secret \
            --secret-id "$SECRET_NAME" \
            --secret-string "$USER_PASSWORDS" \
            --region "$REGION" >/dev/null
        log "Secret updated successfully"
    else
        info "Creating new secret..."
        aws secretsmanager create-secret \
            --name "$SECRET_NAME" \
            --description "Cognito user passwords for stack $STACK_NAME" \
            --secret-string "$USER_PASSWORDS" \
            --region "$REGION" >/dev/null
        log "Secret created successfully"
    fi
    
    info "Passwords saved to Secrets Manager (not displayed for security)"
else
    warn "No passwords to save (UserPasswords is empty)"
fi

# --- Summary ---
log "User creation completed successfully"
if [ "$STATUS_CODE" == "207" ]; then
    info "Status: Partial success (some users may have failed)"
else
    info "Status: Success"
fi

# Cleanup
rm -f /tmp/lambda-response.json


