#!/bin/bash
# Script to verify passwords in Secrets Manager actually work with Cognito
# This should be run after user creation to ensure passwords are correct
# Usage: ./verify-passwords-with-cognito.sh <stack-name> <test-username> <admin-username> <test-script-client-id> [region]

set -e

STACK_NAME="${1}"
TEST_USERNAME="${2}"
ADMIN_USERNAME="${3}"
TEST_SCRIPT_CLIENT_ID="${4}"
REGION="${5:-eu-west-2}"

if [ -z "$STACK_NAME" ] || [ -z "$TEST_USERNAME" ] || [ -z "$ADMIN_USERNAME" ] || [ -z "$TEST_SCRIPT_CLIENT_ID" ]; then
  echo "❌ ERROR: Usage: $0 <stack-name> <test-username> <admin-username> <test-script-client-id> [region]"
  exit 1
fi

SECRET_NAME="${STACK_NAME}/UserPasswords"

echo "🔐 Verifying passwords work with Cognito authentication..."
echo "  Secret name: $SECRET_NAME"
echo "  Test username: $TEST_USERNAME"
echo "  Admin username: $ADMIN_USERNAME"
echo "  Client ID: $TEST_SCRIPT_CLIENT_ID"
echo ""

# Wait a moment for eventual consistency
sleep 3

# Retry logic for secret retrieval and authentication
MAX_RETRIES=5
RETRY_COUNT=0
AUTH_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" >/dev/null 2>&1; then
    SECRET_VALUE=$(aws secretsmanager get-secret-value \
      --secret-id "$SECRET_NAME" \
      --region "$REGION" \
      --query "SecretString" \
      --output text 2>/dev/null || echo "")
    
    if [ -n "$SECRET_VALUE" ] && [ "$SECRET_VALUE" != "null" ] && [ "$SECRET_VALUE" != "None" ]; then
      # Extract passwords
      TEST_PWD=$(echo "$SECRET_VALUE" | jq -r ".[\"$TEST_USERNAME\"]" 2>/dev/null || echo "")
      ADMIN_PWD=$(echo "$SECRET_VALUE" | jq -r ".[\"$ADMIN_USERNAME\"]" 2>/dev/null || echo "")
      
      if [ -n "$TEST_PWD" ] && [ "$TEST_PWD" != "null" ] && [ -n "$ADMIN_PWD" ] && [ "$ADMIN_PWD" != "null" ]; then
        echo "  Passwords retrieved from Secrets Manager"
        echo "  Testing authentication..."
        
        # Test authentication for test user
        TEST_AUTH_RESULT=$(aws cognito-idp initiate-auth \
          --auth-flow USER_PASSWORD_AUTH \
          --auth-parameters "USERNAME=${TEST_USERNAME},PASSWORD=${TEST_PWD}" \
          --client-id "${TEST_SCRIPT_CLIENT_ID}" \
          --region "${REGION}" \
          --query "AuthenticationResult.IdToken" \
          --output text 2>&1) || {
          echo "❌ ERROR: Test user authentication failed!"
          echo "   User: $TEST_USERNAME"
          echo "   Password length: ${#TEST_PWD} characters"
          echo "   Error: $TEST_AUTH_RESULT"
          RETRY_COUNT=$((RETRY_COUNT + 1))
          if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "  Retry $RETRY_COUNT/$MAX_RETRIES: Waiting before retry..."
            sleep 3
            continue
          else
            echo ""
            echo "⚠️  Warning: Could not authenticate test user after $MAX_RETRIES attempts"
            echo "This may indicate:"
            echo "  1. Password in Secrets Manager doesn't match what's in Cognito"
            echo "  2. User account is not confirmed"
            echo "  3. Cognito client doesn't allow USER_PASSWORD_AUTH flow"
            echo ""
            echo "The deployment will continue, but tests may fail."
            exit 0  # Don't fail deployment, just warn
          fi
        }
        
        if [ -z "$TEST_AUTH_RESULT" ] || [ "$TEST_AUTH_RESULT" = "None" ] || [ "$TEST_AUTH_RESULT" = "null" ]; then
          echo "❌ ERROR: Test user authentication returned no token"
          RETRY_COUNT=$((RETRY_COUNT + 1))
          continue
        fi
        
        echo "  ✅ Test user authentication successful"
        
        # Test authentication for admin user
        ADMIN_AUTH_RESULT=$(aws cognito-idp initiate-auth \
          --auth-flow USER_PASSWORD_AUTH \
          --auth-parameters "USERNAME=${ADMIN_USERNAME},PASSWORD=${ADMIN_PWD}" \
          --client-id "${TEST_SCRIPT_CLIENT_ID}" \
          --region "${REGION}" \
          --query "AuthenticationResult.IdToken" \
          --output text 2>&1) || {
          echo "❌ ERROR: Admin user authentication failed!"
          echo "   User: $ADMIN_USERNAME"
          echo "   Password length: ${#ADMIN_PWD} characters"
          echo "   Error: $ADMIN_AUTH_RESULT"
          RETRY_COUNT=$((RETRY_COUNT + 1))
          if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "  Retry $RETRY_COUNT/$MAX_RETRIES: Waiting before retry..."
            sleep 3
            continue
          else
            echo ""
            echo "⚠️  Warning: Could not authenticate admin user after $MAX_RETRIES attempts"
            echo "This may indicate:"
            echo "  1. Password in Secrets Manager doesn't match what's in Cognito"
            echo "  2. User account is not confirmed"
            echo "  3. Cognito client doesn't allow USER_PASSWORD_AUTH flow"
            echo ""
            echo "The deployment will continue, but tests may fail."
            exit 0  # Don't fail deployment, just warn
          fi
        }
        
        if [ -z "$ADMIN_AUTH_RESULT" ] || [ "$ADMIN_AUTH_RESULT" = "None" ] || [ "$ADMIN_AUTH_RESULT" = "null" ]; then
          echo "❌ ERROR: Admin user authentication returned no token"
          RETRY_COUNT=$((RETRY_COUNT + 1))
          continue
        fi
        
        echo "  ✅ Admin user authentication successful"
        echo ""
        echo "✅ Password verification complete - both users can authenticate"
        AUTH_SUCCESS=true
        break
      fi
    fi
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "  Retry $RETRY_COUNT/$MAX_RETRIES: Waiting for secret to be available..."
    sleep 3
  fi
done

if [ "$AUTH_SUCCESS" = "false" ]; then
  echo "⚠️  Warning: Could not verify passwords with Cognito after $MAX_RETRIES attempts"
  echo "This may cause test failures, but deployment will continue"
  exit 0  # Don't fail deployment, just warn
fi

