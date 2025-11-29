#!/bin/bash
# Script to validate passwords by testing authentication with Cognito
# Usage: ./validate-passwords.sh [env-file] [region] [profile]

set -e

ENV_FILE="${1:-.env}"
REGION="${2:-eu-west-2}"
PROFILE="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="${SCRIPT_DIR}/../${ENV_FILE}"

if [ ! -f "${ENV_PATH}" ]; then
  echo "❌ ERROR: .env file not found at: ${ENV_PATH}"
  exit 1
fi

# Build AWS CLI profile argument - only use profile if not in CI and profile is not "default"
AWS_PROFILE_ARG=""
if [ -z "${CI:-}" ] && [ "${PROFILE}" != "default" ] && [ -n "${PROFILE}" ]; then
  AWS_PROFILE_ARG="--profile ${PROFILE}"
fi

echo "🔐 Validating passwords by testing authentication with Cognito..."
echo "   Env file: ${ENV_PATH}"
echo "   Region: ${REGION}"
if [ -n "${PROFILE}" ]; then
  echo "   Profile: ${PROFILE}"
fi
echo ""

# Read required values from .env and trim newlines from passwords
TEST_SCRIPT_CLIENT_ID=$(grep "^TEST_SCRIPT_USER_POOL_CLIENT_ID=" "${ENV_PATH}" 2>/dev/null | cut -d'=' -f2- | tr -d '\n\r' || echo "")
TEST_USERNAME=$(grep "^TEST_USER_EMAIL=" "${ENV_PATH}" 2>/dev/null | cut -d'=' -f2- | tr -d '\n\r' || echo "")
ADMIN_USERNAME=$(grep "^ADMIN_USER_EMAIL=" "${ENV_PATH}" 2>/dev/null | cut -d'=' -f2- | tr -d '\n\r' || echo "")
TEST_PASSWORD=$(grep "^TEST_USER_PASSWORD=" "${ENV_PATH}" 2>/dev/null | cut -d'=' -f2- | tr -d '\n\r' || echo "")
ADMIN_PASSWORD=$(grep "^ADMIN_USER_PASSWORD=" "${ENV_PATH}" 2>/dev/null | cut -d'=' -f2- | tr -d '\n\r' || echo "")

# Validate required values are present
if [ -z "$TEST_SCRIPT_CLIENT_ID" ]; then
  echo "❌ ERROR: TEST_SCRIPT_USER_POOL_CLIENT_ID not found in .env file"
  exit 1
fi

if [ -z "$TEST_USERNAME" ]; then
  echo "❌ ERROR: TEST_USER_EMAIL not found in .env file"
  exit 1
fi

if [ -z "$ADMIN_USERNAME" ]; then
  echo "❌ ERROR: ADMIN_USER_EMAIL not found in .env file"
  exit 1
fi

if [ -z "$TEST_PASSWORD" ]; then
  echo "❌ ERROR: TEST_USER_PASSWORD not found in .env file"
  exit 1
fi

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "❌ ERROR: ADMIN_USER_PASSWORD not found in .env file"
  exit 1
fi

# Function to test authentication
test_authentication() {
  local username="$1"
  local password="$2"
  local user_type="$3"
  
  echo "  Testing authentication for ${user_type} user: $username"
  
  # Attempt authentication
  AUTH_RESULT=$(aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --auth-parameters "USERNAME=${username},PASSWORD=${password}" \
    --client-id "${TEST_SCRIPT_CLIENT_ID}" \
    ${AWS_PROFILE_ARG} \
    --region "${REGION}" \
    --query "AuthenticationResult.IdToken" \
    --output text 2>&1) || {
    echo "❌ ERROR: ${user_type} user authentication failed!"
    echo "   User: $username"
    echo "   Client ID: $TEST_SCRIPT_CLIENT_ID"
    echo "   Password length: ${#password} characters"
    echo ""
    echo "   Error details:"
    echo "$AUTH_RESULT" | head -10
    echo ""
    echo "   This usually means:"
    echo "   1. The password in Secrets Manager is incorrect"
    echo "   2. The user password was not set correctly in Cognito"
    echo "   3. The user account is not confirmed"
    echo "   4. The Cognito client doesn't allow USER_PASSWORD_AUTH flow"
    echo ""
    echo "   Check the 'Create Cognito Users' step in the deploy job to ensure passwords were created correctly."
    return 1
  }
  
  # Check if we got a valid token
  if [ -z "$AUTH_RESULT" ] || [ "$AUTH_RESULT" = "None" ] || [ "$AUTH_RESULT" = "null" ]; then
    echo "❌ ERROR: ${user_type} user authentication returned no token!"
    echo "   User: $username"
    echo "   Response: $AUTH_RESULT"
    return 1
  fi
  
  # Verify it looks like a JWT token (starts with eyJ)
  if [[ ! "$AUTH_RESULT" =~ ^eyJ ]]; then
    echo "❌ ERROR: ${user_type} user authentication returned invalid token format!"
    echo "   User: $username"
    echo "   Response: $AUTH_RESULT"
    return 1
  fi
  
  echo "  ✅ ${user_type} user authentication successful"
  return 0
}

# Test authentication for test user
if ! test_authentication "$TEST_USERNAME" "$TEST_PASSWORD" "test"; then
  exit 1
fi

echo ""

# Test authentication for admin user
if ! test_authentication "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "admin"; then
  exit 1
fi

echo ""
echo "✅ Password validation complete - both users can authenticate successfully"

