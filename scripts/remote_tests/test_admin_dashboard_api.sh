#!/bin/bash
# Test script for Admin Dashboard Lambda endpoints

set -e
set -o pipefail

STACK_NAME="${STACK_NAME:-uktv-event-streaming-app}"
PROFILE="streaming"
REGION="eu-west-2"
ADMIN_PASSWORD="A-Strong-P@ssw0rd1"

log() { echo "✅ $1"; }
error() { echo "❌ ERROR: $1" >&2; exit 1; }

# 1. Fetch Outputs
log "Fetching stack outputs..."
STACK_OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs" --profile "$PROFILE" --region "$REGION")
get_output() { echo "$STACK_OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"; }

ADMIN_API_ENDPOINT=$(get_output "AdminApiEndpoint")
ADMIN_USERNAME=$(get_output "AdminUsername")
USER_POOL_CLIENT_ID=$(get_output "TestScriptUserPoolClientId")
USER_PREFS_LAMBDA_ARN=$(aws lambda get-function --function-name $(get_output "UserPreferencesFunctionName") --query 'Configuration.FunctionArn' --output text --profile "$PROFILE" --region "$REGION")

if [ -z "$ADMIN_API_ENDPOINT" ]; then error "AdminApiEndpoint not found"; fi

# 2. Authenticate
log "Authenticating..."
ID_TOKEN=$(aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --auth-parameters "USERNAME=${ADMIN_USERNAME},PASSWORD=${ADMIN_PASSWORD}" \
    --client-id "${USER_POOL_CLIENT_ID}" \
    --query "AuthenticationResult.IdToken" \
    --output text \
    --profile "$PROFILE" --region "$REGION")

# 3. Test GET /admin/system/lambdas
log "Testing GET /admin/system/lambdas..."
LAMBDAS_RESP=$(curl -s -f -H "Authorization: ${ID_TOKEN}" "${ADMIN_API_ENDPOINT}/admin/system/lambdas")

# Verify structure
COUNT=$(echo "$LAMBDAS_RESP" | jq '.lambdas | length')
if [ "$COUNT" -lt 1 ]; then error "No lambdas returned in summary"; fi
log "Found $COUNT monitored lambdas."

# 4. Test POST /admin/system/lambdas/logs
# We use the User Preferences Lambda for testing as we know its ARN
log "Testing POST /admin/system/lambdas/logs for UserPreferences..."
LOGS_RESP=$(curl -s -f -X POST \
  -H "Authorization: ${ID_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"function_arn\": \"$USER_PREFS_LAMBDA_ARN\"}" \
  "${ADMIN_API_ENDPOINT}/admin/system/lambdas/logs")

# Verify structure
LOG_GROUP=$(echo "$LOGS_RESP" | jq -r '.log_group')
if [[ "$LOG_GROUP" != *"/aws/lambda/"* ]]; then error "Invalid log group in response"; fi
log "Retrieved logs for: $LOG_GROUP"

echo "🎉 Admin Dashboard API tests passed!"