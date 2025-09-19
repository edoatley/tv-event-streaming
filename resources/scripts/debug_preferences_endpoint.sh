#!/bin/bash
# A diagnostic script to debug the GET /preferences endpoint step-by-step.
# It captures detailed logs and infrastructure state upon failure.

# --- Configuration ---
STACK_NAME="uktv-event-streaming-app"
PROFILE="streaming"
REGION="eu-west-2"
TEST_USER_PASSWORD="A-Strong-P@ssw0rd1"

# --- Helper Functions ---
log() {
    echo -e "\n✅ $1"
}

info() {
    echo "   - $1"
}

error() {
    echo -e "\n❌ ERROR: $1" >&2
    exit 1
}

diag_header() {
    echo -e "\n\n========================================================================"
    echo "🔬 DIAGNOSTIC INFORMATION: $1"
    echo "========================================================================"
}

# --- Main Script ---
log "Step 1: Checking prerequisites..."
if ! command -v jq &> /dev/null; then error "jq is not installed. Please install it."; fi
if ! command -v curl &> /dev/null; then error "curl is not installed. Please install it."; fi
if ! command -v aws &> /dev/null; then error "AWS CLI is not installed. Please install it."; fi
info "Prerequisites check passed (jq, curl, aws cli are installed)."

log "Step 2: Checking AWS SSO session for profile: ${PROFILE}..."
if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
    info "AWS SSO session expired or not found. Please log in."
    aws sso login --profile "${PROFILE}"
    if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
        error "AWS login failed. Please check your configuration. Aborting."
    fi
fi
info "AWS SSO session is active."

log "Step 3: Fetching required outputs from stack '$STACK_NAME'..."
STACK_OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs" --profile "$PROFILE" --region "$REGION")

get_output_value() {
    echo "$STACK_OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"
}

API_ENDPOINT=$(get_output_value "WebApiEndpoint")
USER_POOL_ID=$(get_output_value "UserPoolId")
USER_POOL_CLIENT_ID=$(get_output_value "TestScriptUserPoolClientId")
TEST_USERNAME=$(get_output_value "TestUsername")

# Validation
if [ -z "$API_ENDPOINT" ]; then error "Failed to retrieve WebApiEndpoint from stack outputs."; fi
if [ -z "$USER_POOL_ID" ]; then error "Failed to retrieve UserPoolId from stack outputs."; fi
if [ -z "$USER_POOL_CLIENT_ID" ]; then error "Failed to retrieve TestScriptUserPoolClientId from stack outputs."; fi
if [ -z "$TEST_USERNAME" ]; then error "Failed to retrieve TestUsername from stack outputs."; fi
info "Successfully fetched all required stack outputs."
info "API Endpoint: $API_ENDPOINT"

log "Step 3.5: Fetching nested stack resources for diagnostics..."
NESTED_STACK_NAME=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --logical-resource-id WebApiApp --query "StackResources[0].PhysicalResourceId" --output text --profile "$PROFILE" --region "$REGION" 2>/dev/null | cut -d'/' -f2)

if [ -z "$NESTED_STACK_NAME" ]; then
    info "⚠️  Could not determine nested stack name for WebApiApp. CloudWatch log fetching will be disabled."
    WEB_API_ID=""
else
    WEB_API_ID=$(aws cloudformation describe-stack-resources --stack-name "$NESTED_STACK_NAME" --logical-resource-id WebApi --query "StackResources[0].PhysicalResourceId" --output text --profile "$PROFILE" --region "$REGION" 2>/dev/null)
    if [ -z "$WEB_API_ID" ]; then
        info "⚠️  Could not determine Web API ID from nested stack. CloudWatch log fetching will be disabled."
    else
        info "Found Web API ID for diagnostics: $WEB_API_ID"
    fi
fi

log "Step 4: Authenticating test user '$TEST_USERNAME' with Cognito..."
ID_TOKEN=$(aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --client-id "$USER_POOL_CLIENT_ID" \
    --auth-parameters "USERNAME=$TEST_USERNAME,PASSWORD=$TEST_USER_PASSWORD" \
    --query "AuthenticationResult.IdToken" \
    --output text \
    --profile "$PROFILE" --region "$REGION")

if [ -z "$ID_TOKEN" ]; then
    error "Cognito authentication failed. Could not get an ID Token."
fi
info "Successfully authenticated and obtained ID token."
info "ID Token: ${ID_TOKEN:0:10}..."

log "Step 5: Making API call to GET /preferences..."
CURL_COMMAND="curl -v -s -X GET -H \"Authorization: ${ID_TOKEN}\" \"${API_ENDPOINT}/preferences\""

info "Executing command..."

# Execute curl and capture stdout, stderr, and http_code
BODY_FILE=$(mktemp)
CURL_STDERR_FILE=$(mktemp)
HTTP_CODE=$(curl -v -s -w "%{http_code}" -X GET \
    -H "Authorization: ${ID_TOKEN}" \
    "${API_ENDPOINT}/preferences" \
    -o "$BODY_FILE" 2> "$CURL_STDERR_FILE")

BODY=$(<"$BODY_FILE")
CURL_STDERR=$(<"$CURL_STDERR_FILE")
rm "$BODY_FILE" "$CURL_STDERR_FILE"

info "Request completed with HTTP Status Code: $HTTP_CODE"

# --- Analysis ---
if [[ "$HTTP_CODE" =~ ^2[0-9]{2}$ ]]; then
    log "🎉 SUCCESS! Request to GET /preferences was successful (Status: $HTTP_CODE)."
    info "Response Body:"
    echo "$BODY" | jq .
    exit 0
else
    echo -e "\n❌ ERROR: Request to GET /preferences FAILED with status $HTTP_CODE." >&2

    diag_header "Failed Request Details"
    echo "HTTP Status Code: $HTTP_CODE"
    echo -e "\n--- Response Body ---"
    echo "$BODY"
    echo -e "\n--- cURL Verbose Output (stderr) ---"
    echo "$CURL_STDERR"

    # Extract Request ID from headers if available
    REQUEST_ID=$(echo "$CURL_STDERR" | grep -i '< x-amzn-requestid:' | awk -F': ' '{print $2}' | tr -d '\r')

    diag_header "Infrastructure State Analysis"
    if [ -n "$WEB_API_ID" ]; then
        RESOURCE_ID=$(aws apigateway get-resources --rest-api-id "$WEB_API_ID" --profile "$PROFILE" | jq -r '.items[] | select(.path=="/preferences") | .id')
        info "Found Resource ID for /preferences: $RESOURCE_ID"

        if [ -n "$RESOURCE_ID" ]; then
            echo -e "\n--- Configuration for GET /preferences Method ---"
            aws apigateway get-method --rest-api-id "$WEB_API_ID" --resource-id "$RESOURCE_ID" --http-method GET --profile "$PROFILE" | jq .
        else
            echo "Could not find resource for /preferences path."
        fi
    else
        echo "Skipping infrastructure analysis because Web API ID could not be determined."
    fi

    if [ -n "$WEB_API_ID" ]; then
        diag_header "CloudWatch Execution Log Analysis"
        # Get stage info to find the exact log group ARNs
        STAGE_INFO=$(aws apigateway get-stage --rest-api-id "$WEB_API_ID" --stage-name Prod --profile "$PROFILE" --region "$REGION")
        
        # Define potential log groups by inspecting the deployed stage
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
            max_wait_time=300
            interval=5
            end_time=$(( $(date +%s) + max_wait_time ))
            LOGS_FOUND=false

            while [[ $(date +%s) -lt $end_time && "$LOGS_FOUND" == "false" ]]; do
                for LOG_GROUP_NAME in "${LOG_GROUPS_TO_SEARCH[@]}"; do
                    info "--> Describing recent streams in log group: $LOG_GROUP_NAME"

                    # Get the 5 most recent log streams to target our search
                    # Use jq to create a newline-separated list for easy iteration in bash
                    RECENT_STREAMS_LIST=$(aws logs describe-log-streams \
                        --log-group-name "$LOG_GROUP_NAME" \
                        --order-by LastEventTime \
                        --descending \
                        --limit 5 \
                        --profile "$PROFILE" --region "$REGION" | jq -r '.logStreams[].logStreamName')

                    if [ -z "$RECENT_STREAMS_LIST" ]; then
                        info "    No recent log streams found in this group yet."
                        continue
                    fi

                    # Loop through each recent stream individually
                    while IFS= read -r STREAM_NAME; do
                        if [ -z "$STREAM_NAME" ]; then continue; fi
                        info "    --> Checking stream: $STREAM_NAME"

                        LOGS=$(aws logs filter-log-events \
                            --log-group-name "$LOG_GROUP_NAME" \
                            --log-stream-names "$STREAM_NAME" \
                            --filter-pattern "$REQUEST_ID" \
                            --profile "$PROFILE" --region "$REGION" | jq -r '.events[].message')

                        if [ -n "$LOGS" ]; then
                            echo -e "\n--- Found Logs in $LOG_GROUP_NAME (Stream: $STREAM_NAME) ---"
                            echo "$LOGS"
                            LOGS_FOUND=true
                            break 2 # Exit both the inner stream loop and the outer group loop
                        fi
                    done <<< "$RECENT_STREAMS_LIST"

                    if [ "$LOGS_FOUND" == "true" ]; then
                        break # Exit the outer group loop if logs were found
                    fi
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
    else
        diag_header "CloudWatch Log Analysis"
        echo "Web API ID is missing. Unable to perform log search."
    fi

    exit 1
fi