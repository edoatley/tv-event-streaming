#!/bin/bash
# Script to verify passwords are stored in Secrets Manager after user creation
# Usage: ./verify-passwords-in-secrets-manager.sh <stack-name> <test-username> <admin-username> [region] [profile]

set -e

STACK_NAME="${1}"
TEST_USERNAME="${2}"
ADMIN_USERNAME="${3}"
REGION="${4:-eu-west-2}"
PROFILE="${5:-}"

if [ -z "$STACK_NAME" ] || [ -z "$TEST_USERNAME" ] || [ -z "$ADMIN_USERNAME" ]; then
  echo "❌ ERROR: Usage: $0 <stack-name> <test-username> <admin-username> [region] [profile]"
  exit 1
fi

# Build AWS CLI profile argument - only use profile if not in CI and profile is not "default"
AWS_PROFILE_ARG=""
if [ -z "${CI:-}" ] && [ "${PROFILE}" != "default" ] && [ -n "${PROFILE}" ]; then
  AWS_PROFILE_ARG="--profile ${PROFILE}"
fi

SECRET_NAME="${STACK_NAME}/UserPasswords"

echo "Verifying passwords are stored in Secrets Manager..."
echo "  Secret name: $SECRET_NAME"
echo "  Test username: $TEST_USERNAME"
echo "  Admin username: $ADMIN_USERNAME"
echo ""

# Wait a moment for eventual consistency
sleep 2

# Retry logic for secret retrieval
MAX_RETRIES=5
RETRY_COUNT=0
SECRET_RETRIEVED=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" ${AWS_PROFILE_ARG} --region "$REGION" >/dev/null 2>&1; then
    SECRET_VALUE=$(aws secretsmanager get-secret-value \
      --secret-id "$SECRET_NAME" \
      ${AWS_PROFILE_ARG} \
      --region "$REGION" \
      --query "SecretString" \
      --output text 2>/dev/null || echo "")
    
    if [ -n "$SECRET_VALUE" ] && [ "$SECRET_VALUE" != "null" ] && [ "$SECRET_VALUE" != "None" ]; then
      # Verify we can extract passwords
      TEST_PWD=$(echo "$SECRET_VALUE" | jq -r ".[\"$TEST_USERNAME\"]" 2>/dev/null || echo "")
      ADMIN_PWD=$(echo "$SECRET_VALUE" | jq -r ".[\"$ADMIN_USERNAME\"]" 2>/dev/null || echo "")
      
      if [ -n "$TEST_PWD" ] && [ "$TEST_PWD" != "null" ] && [ -n "$ADMIN_PWD" ] && [ "$ADMIN_PWD" != "null" ]; then
        echo "✅ Passwords verified in Secrets Manager"
        echo "  Test user password length: ${#TEST_PWD} characters"
        echo "  Admin user password length: ${#ADMIN_PWD} characters"
        SECRET_RETRIEVED=true
        break
      else
        echo "  ⚠️  Warning: Passwords found in secret but could not extract values"
        echo "     Test password extracted: $([ -n "$TEST_PWD" ] && [ "$TEST_PWD" != "null" ] && echo "yes" || echo "no")"
        echo "     Admin password extracted: $([ -n "$ADMIN_PWD" ] && [ "$ADMIN_PWD" != "null" ] && echo "yes" || echo "no")"
      fi
    fi
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "  Retry $RETRY_COUNT/$MAX_RETRIES: Waiting for secret to be available..."
    sleep 2
  fi
done

if [ "$SECRET_RETRIEVED" = "false" ]; then
  echo "⚠️  Warning: Could not verify passwords in Secrets Manager after $MAX_RETRIES attempts"
  echo "This may cause test failures, but deployment will continue"
  echo ""
  echo "Troubleshooting:"
  echo "  1. Check that the 'Create Cognito Users' step completed successfully"
  echo "  2. Verify the Lambda function saved passwords to Secrets Manager"
  echo "  3. Check CloudWatch logs for the UserCreation Lambda function"
  exit 0  # Don't fail the deployment, just warn
fi

