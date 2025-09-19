#!/bin/bash
# This script runs a series of tests against the deployed Web API endpoints
# to validate their functionality.

set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # The return value of a pipeline is the status of the last command to exit with a non-zero status.

# --- Configuration ---
STACK_NAME="uktv-event-streaming-app"
PROFILE="streaming"
REGION="eu-west-2"
TEST_USER_PASSWORD="A-Strong-P@ssw0rd1" # This should match the password set in remote_deploy.sh

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

# Function to make API calls
# Usage: api_curl <method> <path> [json_data] [auth_flag]
# It uses global variables: API_ENDPOINT, API_KEY, ID_TOKEN
api_curl() {
    local method=$1
    local path=$2
    local data=$3
    local headers=()
    local BODY_FILE=$(mktemp)
    local CURL_STDERR_FILE=$(mktemp)
    local HTTP_CODE

    if [ -z "$ID_TOKEN" ]; then
        error "ID_TOKEN is not set for authenticated request to $path"
    else
        headers+=("-H" "Authorization: $ID_TOKEN")
    fi

    if [ -n "$data" ]; then
        headers+=("-H" "Content-Type: application/json")
        HTTP_CODE=$(curl -v -s -w "%{http_code}" -X "$method" "${headers[@]}" -d "$data" "${API_ENDPOINT}${path}" -o "$BODY_FILE" 2> "$CURL_STDERR_FILE")
    else
        HTTP_CODE=$(curl -v -s -w "%{http_code}" -X "$method" "${headers[@]}" "${API_ENDPOINT}${path}" -o "$BODY_FILE" 2> "$CURL_STDERR_FILE")
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

        if [ -n "$WEB_API_ID" ]; then
            diag_header "CloudWatch Execution Log Analysis"
            STAGE_INFO=$(aws apigateway get-stage --rest-api-id "$WEB_API_ID" --stage-name Prod --profile "$PROFILE" --region "$REGION")
            EXECUTION_LOG_GROUP="API-Gateway-Execution-Logs_${WEB_API_ID}/Prod"
            ACCESS_LOG_ARN=$(echo "$STAGE_INFO" | jq -r '.accessLogSettings.destinationArn // empty')
            ACCESS_LOG_GROUP=""
            if [ -n "$ACCESS_LOG_ARN" ]; then
                ACCESS_LOG_GROUP=$(echo "$ACCESS_LOG_ARN" | cut -d':' -f7)
            fi

            LOG_GROUPS_TO_SEARCH=()
            [ -n "$EXECUTION_LOG_GROUP" ] && LOG_GROUPS_TO_SEARCH+=("$EXECUTION_LOG_GROUP")
            [ -n "$ACCESS_LOG_GROUP" ] && LOG_GROUPS_TO_SEARCH+=("$ACCESS_LOG_GROUP")

            if [ -z "$REQUEST_ID" ]; then
                echo "Could not find x-amzn-requestid in response headers. Unable to perform targeted log search."
            elif [ ${#LOG_GROUPS_TO_SEARCH[@]} -eq 0 ]; then
                echo "Could not identify any CloudWatch log groups from the API Gateway stage configuration."
            else
                info "Searching for Request ID: $REQUEST_ID..."
                max_wait_time=45
                interval=5
                end_time=$(( $(date +%s) + max_wait_time ))
                LOGS_FOUND=false

                while [[ $(date +%s) -lt $end_time && "$LOGS_FOUND" == "false" ]]; do
                    for LOG_GROUP_NAME in "${LOG_GROUPS_TO_SEARCH[@]}"; do
                        info "--> Describing recent streams in log group: $LOG_GROUP_NAME"
                        RECENT_STREAMS_LIST=$(aws logs describe-log-streams --log-group-name "$LOG_GROUP_NAME" --order-by LastEventTime --descending --limit 5 --profile "$PROFILE" --region "$REGION" | jq -r '.logStreams[].logStreamName')
                        if [ -z "$RECENT_STREAMS_LIST" ]; then
                            info "    No recent log streams found in this group yet."
                            continue
                        fi
                        while IFS= read -r STREAM_NAME; do
                            if [ -z "$STREAM_NAME" ]; then continue; fi
                            info "    --> Checking stream: $STREAM_NAME"
                            LOGS=$(aws logs filter-log-events --log-group-name "$LOG_GROUP_NAME" --log-stream-names "$STREAM_NAME" --filter-pattern "$REQUEST_ID" --profile "$PROFILE" --region "$REGION" | jq -r '.events[].message')
                            if [ -n "$LOGS" ]; then
                                echo -e "\n--- Found Logs in $LOG_GROUP_NAME (Stream: $STREAM_NAME) ---"
                                echo "$LOGS"
                                LOGS_FOUND=true
                                break 2
                            fi
                        done <<< "$RECENT_STREAMS_LIST"
                        if [ "$LOGS_FOUND" == "true" ]; then break; fi
                    done
                    if [ "$LOGS_FOUND" == "false" ]; then
                        remaining_time=$(( end_time - $(date +%s) ))
                        if [[ $remaining_time -gt 0 ]]; then
                            info "Logs not found yet. Retrying for another ${remaining_time}s..."
                            sleep $interval
                        fi
                    fi
                done
                if [ "$LOGS_FOUND" == "false" ]; then
                    echo -e "\n--- No Logs Found ---"
                    echo "Could not find logs for request ID '$REQUEST_ID' after waiting for ${max_wait_time} seconds."
                    echo "Searched in the following log groups:"
                    printf " - %s\n" "${LOG_GROUPS_TO_SEARCH[@]}"
                fi
            fi
        fi
        exit 1
    fi

    echo "$BODY"
}

# --- Main Script ---
echo "🚀 Starting Web API Integration Tests..."

# Step 0: Prerequisite check
if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install it to run these tests (e.g., 'brew install jq' or 'sudo apt-get install jq')."
fi
log "Prerequisite check passed (jq is installed)."

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

# Step 2: Fetch Stack Outputs
log "Step 2: Fetching required outputs from stack '$STACK_NAME'..."
API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='WebApiEndpoint'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")
USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")
USER_POOL_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='TestScriptUserPoolClientId'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")
TEST_USERNAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='TestUsername'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")

log "Step 2.1: Fetching nested stack resources for diagnostics..."
NESTED_STACK_NAME=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --logical-resource-id WebApiApp --query "StackResources[0].PhysicalResourceId" --output text --profile "$PROFILE" --region "$REGION" 2>/dev/null | cut -d'/' -f2)
WEB_API_ID=""
if [ -n "$NESTED_STACK_NAME" ]; then
    WEB_API_ID=$(aws cloudformation describe-stack-resources --stack-name "$NESTED_STACK_NAME" --logical-resource-id WebApi --query "StackResources[0].PhysicalResourceId" --output text --profile "$PROFILE" --region "$REGION" 2>/dev/null)
fi

if [ -z "$WEB_API_ID" ]; then
    info "⚠️  Could not determine Web API ID from nested stack. CloudWatch log fetching will be disabled on failure."
fi

if [ -z "$API_ENDPOINT" ] || [ -z "$USER_POOL_ID" ] || [ -z "$USER_POOL_CLIENT_ID" ] || [ -z "$TEST_USERNAME" ]; then
    error "Failed to retrieve one or more required stack outputs. Aborting."
fi
log "Successfully fetched stack outputs."
info "API Endpoint: $API_ENDPOINT"
info "Test Username: $TEST_USERNAME"
info "User Pool ID and Client ID: $USER_POOL_ID, $USER_POOL_CLIENT_ID"

# Step 3: Authenticate with Cognito
log "Step 3: Authenticating test user '$TEST_USERNAME' with Cognito..."
AUTH_RESPONSE=$(aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --client-id "$USER_POOL_CLIENT_ID" \
    --auth-parameters "USERNAME=$TEST_USERNAME,PASSWORD=$TEST_USER_PASSWORD" \
    --query "AuthenticationResult.IdToken" \
    --output text \
    --profile "$PROFILE" --region "$REGION")

if [ -z "$AUTH_RESPONSE" ]; then
    error "Cognito authentication failed. Please check user credentials and pool configuration."
fi
ID_TOKEN=$AUTH_RESPONSE
log "Successfully authenticated and obtained ID token."
info "Cognito returned a valid JWT for the test user."

# Step 3.5: Save original preferences and test titles with them
log "Step 3.5: Fetching original preferences to test with and restore later..."
ORIGINAL_PREFS=$(api_curl "GET" "/preferences" "")
ORIGINAL_SOURCES_COUNT=$(echo "$ORIGINAL_PREFS" | jq '.sources | length')
ORIGINAL_GENRES_COUNT=$(echo "$ORIGINAL_PREFS" | jq '.genres | length')
log "Found ${ORIGINAL_SOURCES_COUNT} sources and ${ORIGINAL_GENRES_COUNT} genres in original preferences."

# Step 4: Run API Tests
log "Step 4: Starting API endpoint tests..."

# --- Test CORS Preflight ---
log "Testing OPTIONS /preferences (CORS preflight)..."
CORS_RESPONSE_HEADERS=$(curl -s -i -X OPTIONS \
    -H "Access-Control-Request-Method: PUT" \
    -H "Origin: http://localhost:8000" \
    "${API_ENDPOINT}/preferences")

if ! echo "$CORS_RESPONSE_HEADERS" | grep -q -i "access-control-allow-methods:.*PUT"; then
    error "OPTIONS /preferences did not return correct CORS headers for PUT. Headers:\n$CORS_RESPONSE_HEADERS"
fi
if ! echo "$CORS_RESPONSE_HEADERS" | grep -q -i "access-control-allow-origin: \*"; then
    error "OPTIONS /preferences did not return correct CORS headers for Origin. Headers:\n$CORS_RESPONSE_HEADERS"
fi
log "OPTIONS /preferences returned correct CORS headers."
info "Validated Access-Control-Allow-Methods and Access-Control-Allow-Origin headers."

# --- Test Public Endpoints ---
log "Testing GET /sources..."
SOURCES_RESPONSE=$(api_curl "GET" "/sources")
if ! echo "$SOURCES_RESPONSE" | jq -e 'type == "array"' > /dev/null; then
    error "GET /sources did not return a JSON array. Response: $SOURCES_RESPONSE"
fi
SOURCES_COUNT=$(echo "$SOURCES_RESPONSE" | jq 'length')
log "GET /sources returned a valid JSON array."
info "Response is a JSON array with ${SOURCES_COUNT} items."
FIRST_SOURCE_ID=$(echo "$SOURCES_RESPONSE" | jq -r '.[0].id // empty')

log "Testing GET /genres..."
GENRES_RESPONSE=$(api_curl "GET" "/genres")
if ! echo "$GENRES_RESPONSE" | jq -e 'type == "array"' > /dev/null; then
    error "GET /genres did not return a JSON array. Response: $GENRES_RESPONSE"
fi
GENRES_COUNT=$(echo "$GENRES_RESPONSE" | jq 'length')
log "GET /genres returned a valid JSON array."
info "Response is a JSON array with ${GENRES_COUNT} items."
FIRST_GENRE_ID=$(echo "$GENRES_RESPONSE" | jq -r '.[0].id // empty')

# --- Test Protected Endpoints (Phase 1: With existing preferences) ---
log "Testing GET /titles with original preferences..."
TITLES_RESPONSE=$(api_curl "GET" "/titles" "")
if ! echo "$TITLES_RESPONSE" | jq -e 'type == "array"' > /dev/null; then
    error "GET /titles did not return a JSON array. Response: $TITLES_RESPONSE"
fi
TITLES_COUNT=$(echo "$TITLES_RESPONSE" | jq 'length')
log "GET /titles returned a valid JSON array."
info "Found ${TITLES_COUNT} titles based on original user preferences."

log "Testing GET /recommendations with original preferences..."
RECOMMENDATIONS_RESPONSE=$(api_curl "GET" "/recommendations" "")
if ! echo "$RECOMMENDATIONS_RESPONSE" | jq -e 'type == "array"' > /dev/null; then
    error "GET /recommendations did not return a JSON array. Response: $RECOMMENDATIONS_RESPONSE"
fi
RECOMMENDATIONS_COUNT=$(echo "$RECOMMENDATIONS_RESPONSE" | jq 'length')
log "GET /recommendations returned a valid JSON array."
info "Found ${RECOMMENDATIONS_COUNT} recommendations based on original user preferences."

# --- Test Protected Endpoints ---
log "Testing GET /preferences..."
PREFS_RESPONSE=$(api_curl "GET" "/preferences" "")
if ! echo "$PREFS_RESPONSE" | jq -e 'has("sources") and has("genres")' > /dev/null; then
    error "GET /preferences did not return the expected JSON structure. Response: $PREFS_RESPONSE"
fi
log "GET /preferences returned a valid structure."
info "Response contains 'sources' and 'genres' keys."

log "Testing PUT /preferences..."
if [ -z "$FIRST_SOURCE_ID" ] || [ -z "$FIRST_GENRE_ID" ]; then
    info "Skipping PUT /preferences test as no source/genre IDs could be found from public endpoints."
else
    UPDATE_PAYLOAD=$(jq -n --arg sid "$FIRST_SOURCE_ID" --arg gid "$FIRST_GENRE_ID" \
        '{sources: [$sid], genres: [$gid]}')
    UPDATE_RESPONSE=$(api_curl "PUT" "/preferences" "$UPDATE_PAYLOAD")
    if ! echo "$UPDATE_RESPONSE" | jq -e '.message | contains("updated successfully")' > /dev/null; then
        error "PUT /preferences failed or returned unexpected message. Response: $UPDATE_RESPONSE"
    fi
    log "PUT /preferences was successful."
    info "Received success message from the API."

    # Verify the update
    log "Verifying PUT /preferences with another GET..."
    VERIFY_RESPONSE=$(api_curl "GET" "/preferences" "")
    VERIFIED_SOURCE=$(echo "$VERIFY_RESPONSE" | jq -r '.sources[0]')
    VERIFIED_GENRE=$(echo "$VERIFY_RESPONSE" | jq -r '.genres[0]')

    if [ "$VERIFIED_SOURCE" != "$FIRST_SOURCE_ID" ] || [ "$VERIFIED_GENRE" != "$FIRST_GENRE_ID" ]; then
        error "Verification of PUT /preferences failed. Expected ($FIRST_SOURCE_ID, $FIRST_GENRE_ID), got ($VERIFIED_SOURCE, $VERIFIED_GENRE)."
    fi
    log "Successfully verified preference update."
    info "GET /preferences returned the updated source and genre IDs."
fi

# --- Cleanup ---
log "Cleaning up: Restoring original user preferences..."
api_curl "PUT" "/preferences" "$ORIGINAL_PREFS" > /dev/null
log "Original user preferences restored."
info "Sent back ${ORIGINAL_SOURCES_COUNT} sources and ${ORIGINAL_GENRES_COUNT} genres."

echo ""
echo "🎉 All API tests passed successfully! 🎉"