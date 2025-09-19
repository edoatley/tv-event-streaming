#!/bin/bash
# This script runs integration tests against the deployed Admin API endpoints.

set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # The return value of a pipeline is the status of the last command to exit with a non-zero status.

# --- Configuration ---
STACK_NAME="uktv-event-streaming-app"
PROFILE="streaming"
REGION="eu-west-2"
# This password must match the one in set-cognito-password.sh
ADMIN_PASSWORD="A-Strong-P@ssw0rd1"

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

diag_header() {
    echo -e "\n\n========================================================================"
    echo "🔬 DIAGNOSTIC INFORMATION: $1"
    echo "========================================================================"
}

# Function to make Admin API calls
admin_api_curl() {
    local method=$1
    local path=$2
    local data=$3
    local headers=()
    local BODY_FILE=$(mktemp)
    local CURL_STDERR_FILE=$(mktemp)
    local HTTP_CODE

    if [ -z "$ID_TOKEN" ]; then
        error "ID_TOKEN is not set. Authentication might have failed."
    fi
    # Add the identity token from Cognito to the Authorization header.
    headers+=("-H" "Authorization: ${ID_TOKEN}")

    if [ -n "$data" ]; then
        headers+=("-H" "Content-Type: application/json")
        HTTP_CODE=$(curl -v -s -w "%{http_code}" -X "$method" "${headers[@]}" -d "$data" "${ADMIN_API_ENDPOINT}${path}" -o "$BODY_FILE" 2> "$CURL_STDERR_FILE")
    else
        HTTP_CODE=$(curl -v -s -w "%{http_code}" -X "$method" "${headers[@]}" "${ADMIN_API_ENDPOINT}${path}" -o "$BODY_FILE" 2> "$CURL_STDERR_FILE")
    fi

    BODY=$(<"$BODY_FILE")
    CURL_STDERR=$(<"$CURL_STDERR_FILE")
    rm "$BODY_FILE" "$CURL_STDERR_FILE"

    if ! [[ "$HTTP_CODE" =~ ^2[0-9]{2}$ ]]; then
        echo "❌ ERROR: Request to $method $path failed with status $HTTP_CODE. Body: $BODY" >&2

        diag_header "Failed Request Details"
        echo "HTTP Status Code: $HTTP_CODE"
        echo -e "\n--- Response Body ---\n$BODY"
        echo -e "\n--- cURL Verbose Output (stderr) ---\n$CURL_STDERR"

        REQUEST_ID=$(echo "$CURL_STDERR" | grep -i '< x-amzn-requestid:' | awk -F': ' '{print $2}' | tr -d '\r')

        if [ -n "$REQUEST_ID" ] && [ -n "$ADMIN_API_ID" ]; then
            diag_header "CloudWatch Execution Log Analysis"
            LOG_GROUP_NAME="API-Gateway-Execution-Logs_${ADMIN_API_ID}/Prod"
            info "Searching for logs with Request ID: $REQUEST_ID in log group $LOG_GROUP_NAME"
            info "Waiting 10s for logs to propagate..."
            sleep 10
            
            LOGS=$(aws logs filter-log-events --log-group-name "$LOG_GROUP_NAME" --filter-pattern "$REQUEST_ID" --profile "$PROFILE" --region "$REGION" | jq -r '.events[].message')
            
            if [ -n "$LOGS" ]; then
                echo -e "\n--- Found Execution Logs ---\n$LOGS"
            else
                echo -e "\n--- No Execution Logs Found ---"
                echo "Could not find execution logs for request ID '$REQUEST_ID' in log group '$LOG_GROUP_NAME'."
            fi
        fi
        exit 1
    fi

    echo "$BODY"
}

# --- Main Script ---
echo "🚀 Starting Admin API Integration Tests..."

# Step 0: Prerequisite check
log "Step 0: Checking prerequisites..."
if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install it (e.g., 'brew install jq' or 'sudo apt-get install jq')."
fi
if ! command -v curl &> /dev/null; then
    error "curl is not installed. Please install it."
fi
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it."
fi
log "Prerequisites check passed (jq, curl, aws cli are installed)."

# Step 1: Check AWS session
log "Step 1: Checking AWS SSO session for profile: ${PROFILE}..."
if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
    echo "⚠️ AWS SSO session expired or not found. Please log in."
    aws sso login --profile "${PROFILE}"
    if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
        error "AWS login failed. Please check your configuration. Aborting."
    fi
fi
log "AWS SSO session is active."

# Step 2: Fetch Admin API Stack Outputs
log "Step 2: Fetching required outputs from stack '$STACK_NAME' for Admin API..."
STACK_OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs" --profile "$PROFILE" --region "$REGION")

get_output_value() {
    echo "$STACK_OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"
}

ADMIN_API_ENDPOINT=$(get_output_value "AdminApiEndpoint")
PERIODIC_REFERENCE_FUNCTION_NAME=$(get_output_value "PeriodicReferenceFunctionName")
USER_PREFS_INGESTION_FUNCTION_NAME=$(get_output_value "UserPrefsTitleIngestionFunctionName")
TITLE_ENRICHMENT_FUNCTION_NAME=$(get_output_value "TitleEnrichmentFunctionName")
ADMIN_USERNAME=$(get_output_value "AdminUsername")
USER_POOL_CLIENT_ID=$(get_output_value "TestScriptUserPoolClientId")
NESTED_ADMIN_STACK_NAME=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --logical-resource-id AdminApiApp --query "StackResources[0].PhysicalResourceId" --output text --profile "$PROFILE" | cut -d'/' -f2)
ADMIN_API_ID=$(aws cloudformation describe-stack-resources --stack-name "$NESTED_ADMIN_STACK_NAME" --logical-resource-id AdminApi --query "StackResources[0].PhysicalResourceId" --output text --profile "$PROFILE")

if [ -z "$ADMIN_API_ENDPOINT" ]; then
    error "Failed to retrieve Admin API endpoint or API Key from stack outputs. Aborting."
fi

if [ -z "$ADMIN_API_ID" ]; then
    info "⚠️ Could not retrieve Admin API ID. CloudWatch log fetching will be disabled."
fi

log "Successfully fetched API and function details."
info "Admin API Endpoint: $ADMIN_API_ENDPOINT"

# Step 2.5: Authenticate as Admin User to get JWT token
log "Step 2.5: Authenticating as admin user to get JWT token..."
if [ -z "$ADMIN_USERNAME" ] || [ -z "$USER_POOL_CLIENT_ID" ]; then
    error "Could not retrieve Cognito details (AdminUsername, TestScriptUserPoolClientId) from stack outputs."
fi

info "Attempting to authenticate user: $ADMIN_USERNAME"
ID_TOKEN=$(aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --auth-parameters "USERNAME=${ADMIN_USERNAME},PASSWORD=${ADMIN_PASSWORD}" \
    --client-id "${USER_POOL_CLIENT_ID}" \
    --query "AuthenticationResult.IdToken" \
    --output text \
    --profile "$PROFILE" \
    --region "$REGION")

if [ -z "$ID_TOKEN" ]; then
    error "Failed to get ID token from Cognito. Check admin user credentials and Cognito configuration."
fi
log "Successfully authenticated and retrieved ID token."

# Step 3: Test Admin API Endpoints
log "Step 3: Starting Admin API endpoint tests..."

# --- Test GET /admin/dynamodb/summary ---
log "Testing GET /admin/dynamodb/summary..."
SUMMARY_RESPONSE=$(admin_api_curl "GET" "/admin/dynamodb/summary")
info "DynamoDB Summary Response: $SUMMARY_RESPONSE"

# --- Test POST /admin/data/reference/refresh ---
log "Testing POST /admin/reference/refresh..."
REFRESH_PAYLOAD='{"refresh_sources": "Y", "refresh_genres": "Y", "regions": "GB"}'
admin_api_curl "POST" "/admin/reference/refresh" "$REFRESH_PAYLOAD" > /dev/null 2>&1
log "POST /admin/reference/refresh initiated. Waiting for logs..."
sleep 20 # Wait for logs to be generated
./resources/scripts/get_lambda_logs.sh "$PERIODIC_REFERENCE_FUNCTION_NAME" "$PROFILE" "$REGION"

# --- Test POST /admin/titles/refresh ---
log "Testing POST /admin/titles/refresh..."
admin_api_curl "POST" "/admin/titles/refresh" '{}' > /dev/null 2>&1
log "POST /admin/titles/refresh initiated. Waiting for logs..."
sleep 20 # Wait for logs to be generated
./resources/scripts/get_lambda_logs.sh "$USER_PREFS_INGESTION_FUNCTION_NAME" "$PROFILE" "$REGION"


# --- Test POST /admin/titles/enrich ---
log "Testing POST /admin/titles/enrich..."
admin_api_curl "POST" "/admin/titles/enrich" '{}' > /dev/null 2>&1
log "POST /admin/titles/enrich initiated. Waiting for logs..."
sleep 20 # Wait for logs to be generated
./resources/scripts/get_lambda_logs.sh "$TITLE_ENRICHMENT_FUNCTION_NAME" "$PROFILE" "$REGION"

echo ""
echo "🎉 All Admin API integration tests passed successfully! 🎉"
exit 0
