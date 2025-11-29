#!/bin/bash
# Test script for Admin Dashboard Lambda endpoints

set -e
set -o pipefail

STACK_NAME="${STACK_NAME:-tv-event-streaming-gha}"
PROFILE="streaming"
REGION="eu-west-2"

log() { echo "✅ $1"; }
error() { echo "❌ ERROR: $1" >&2; exit 1; }
warn() { echo "⚠️  WARNING: $1" >&2; }

# 1. Fetch Outputs
log "Fetching stack outputs..."
STACK_OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs" --profile "$PROFILE" --region "$REGION")
get_output() { echo "$STACK_OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"; }

ADMIN_API_ENDPOINT=$(get_output "AdminApiEndpoint")
ADMIN_USERNAME=$(get_output "AdminUsername")
USER_POOL_CLIENT_ID=$(get_output "TestScriptUserPoolClientId")

# Get admin password: try environment variable, then Secrets Manager, then fallback
# Note: The password in Secrets Manager may be different from what's set in Cognito
if [ -z "${ADMIN_PASSWORD:-}" ]; then
    log "ADMIN_PASSWORD not set, attempting to fetch from Secrets Manager..."
    SECRET_NAME="${STACK_NAME}/UserPasswords"
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
        log "Found secret in Secrets Manager, retrieving password..."
        USER_PASSWORDS_JSON=$(aws secretsmanager get-secret-value \
            --secret-id "$SECRET_NAME" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query "SecretString" \
            --output text)
        
        if [ -n "$USER_PASSWORDS_JSON" ] && [ "$USER_PASSWORDS_JSON" != "None" ]; then
            SECRET_PASSWORD=$(echo "$USER_PASSWORDS_JSON" | jq -r ".[\"$ADMIN_USERNAME\"]")
            if [ -n "$SECRET_PASSWORD" ] && [ "$SECRET_PASSWORD" != "null" ]; then
                ADMIN_PASSWORD="$SECRET_PASSWORD"
                log "Password retrieved from Secrets Manager"
            else
                warn "Password not found in Secrets Manager for user: $ADMIN_USERNAME"
            fi
        else
            warn "Secret exists but contains no data"
        fi
    else
        warn "Secret $SECRET_NAME not found in Secrets Manager"
    fi
fi

# Fail if password is still not set - no hardcoded fallback for security
if [ -z "${ADMIN_PASSWORD:-}" ]; then
    error "ADMIN_PASSWORD is not set and could not be retrieved from Secrets Manager."
    error "Please either:"
    error "  1. Set ADMIN_PASSWORD environment variable, or"
    error "  2. Ensure the secret '${STACK_NAME}/UserPasswords' exists in Secrets Manager with the password for user '$ADMIN_USERNAME'"
    error "To set the password in Cognito, run:"
    error "  ./scripts/deploy/set-cognito-password.sh <password> $STACK_NAME $PROFILE $REGION"
    exit 1
fi

# Get User Preferences Lambda ARN from nested stack
NESTED_USER_PREFS_STACK_NAME=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --logical-resource-id UserPreferencesApp --query "StackResources[0].PhysicalResourceId" --output text --profile "$PROFILE" --region "$REGION" 2>/dev/null | cut -d'/' -f2)
if [ -n "$NESTED_USER_PREFS_STACK_NAME" ]; then
    USER_PREFS_LAMBDA_ARN=$(aws cloudformation describe-stacks --stack-name "$NESTED_USER_PREFS_STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='UserPreferencesFunctionArn'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")
else
    error "Could not find UserPreferencesApp nested stack"
fi

if [ -z "$ADMIN_API_ENDPOINT" ]; then error "AdminApiEndpoint not found"; fi
if [ -z "$USER_PREFS_LAMBDA_ARN" ] || [ "$USER_PREFS_LAMBDA_ARN" == "None" ]; then error "UserPreferencesFunctionArn not found"; fi

# 2. Authenticate
log "Authenticating as user: $ADMIN_USERNAME..."
AUTH_OUTPUT=$(aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --auth-parameters "USERNAME=${ADMIN_USERNAME},PASSWORD=${ADMIN_PASSWORD}" \
    --client-id "${USER_POOL_CLIENT_ID}" \
    --query "AuthenticationResult.IdToken" \
    --output text \
    --profile "$PROFILE" \
    --region "$REGION" 2>&1) || {
    error "Authentication failed. The password may not be set for user '$ADMIN_USERNAME'."
    error "To set the password, run:"
    error "  ./scripts/deploy/set-cognito-password.sh <password> $STACK_NAME $PROFILE $REGION"
    error "Or set ADMIN_PASSWORD environment variable with the correct password."
    exit 1
}

ID_TOKEN="$AUTH_OUTPUT"
if [ -z "$ID_TOKEN" ] || [ "$ID_TOKEN" == "None" ]; then
    error "Failed to retrieve ID token. Authentication may have failed."
    exit 1
fi

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

# Verify structure - log_group may be missing if no logs exist yet
LOG_GROUP=$(echo "$LOGS_RESP" | jq -r '.log_group // empty')
MESSAGE=$(echo "$LOGS_RESP" | jq -r '.message // empty')

if [ -n "$LOG_GROUP" ]; then
    if [[ "$LOG_GROUP" != *"/aws/lambda/"* ]]; then 
        error "Invalid log group in response: $LOG_GROUP"
    fi
    log "Retrieved logs for: $LOG_GROUP"
elif [ -n "$MESSAGE" ]; then
    log "Logs response: $MESSAGE (this is expected if the function hasn't run yet)"
else
    error "Unexpected response structure: $LOGS_RESP"
fi

echo "🎉 Admin Dashboard API tests passed!"