#!/bin/bash
# Test script to validate password fetching and validation logic locally
# Usage: ./test-password-validation.sh [stack-name] [region] [profile]

set -e

STACK_NAME="${1:-tv-event-streaming-gha}"
REGION="${2:-eu-west-2}"
PROFILE="${3:-streaming}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

echo "🧪 Testing Password Validation Logic"
echo "======================================"
echo "Stack Name: ${STACK_NAME}"
echo "Region: ${REGION}"
echo "Profile: ${PROFILE}"
echo ""

# Step 1: Test fetching stack outputs
echo "📥 Step 1: Testing fetch-stack-outputs.sh..."
if [ -f ".env" ]; then
  echo "   Backing up existing .env file..."
  cp .env .env.backup
fi

./scripts/fetch-stack-outputs.sh "${STACK_NAME}" "${REGION}" "${PROFILE}"

if [ ! -f ".env" ]; then
  echo "❌ ERROR: .env file was not created"
  exit 1
fi

echo "✅ Stack outputs fetched successfully"
echo ""

# Step 2: Verify required values are present
echo "🔍 Step 2: Verifying required values in .env..."
REQUIRED_VARS=(
  "BASE_URL"
  "COGNITO_USER_POOL_ID"
  "COGNITO_CLIENT_ID"
  "TEST_SCRIPT_USER_POOL_CLIENT_ID"
  "TEST_USER_EMAIL"
  "ADMIN_USER_EMAIL"
  "TEST_USER_PASSWORD"
  "ADMIN_USER_PASSWORD"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
  if ! grep -q "^${var}=" .env 2>/dev/null; then
    MISSING_VARS+=("$var")
  fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  echo "❌ ERROR: Missing required variables in .env:"
  printf '   - %s\n' "${MISSING_VARS[@]}"
  exit 1
fi

echo "✅ All required variables present"
echo ""

# Step 3: Check password values are not empty
echo "🔐 Step 3: Checking password values..."
TEST_PWD=$(grep "^TEST_USER_PASSWORD=" .env | cut -d'=' -f2-)
ADMIN_PWD=$(grep "^ADMIN_USER_PASSWORD=" .env | cut -d'=' -f2-)

if [ -z "$TEST_PWD" ]; then
  echo "❌ ERROR: TEST_USER_PASSWORD is empty"
  exit 1
fi

if [ -z "$ADMIN_PWD" ]; then
  echo "❌ ERROR: ADMIN_USER_PASSWORD is empty"
  exit 1
fi

echo "✅ Passwords are present"
echo "   Test password length: ${#TEST_PWD} characters"
echo "   Admin password length: ${#ADMIN_PWD} characters"
echo ""

# Step 4: Test password validation script
echo "🔐 Step 4: Testing validate-passwords.sh..."
./scripts/validate-passwords.sh ".env" "${REGION}" "${PROFILE}"

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ All tests passed!"
  echo ""
  echo "Summary:"
  echo "  ✅ Stack outputs fetched successfully"
  echo "  ✅ All required variables present"
  echo "  ✅ Passwords are not empty"
  echo "  ✅ Passwords authenticate successfully with Cognito"
  echo ""
  
  # Restore backup if it existed
  if [ -f ".env.backup" ]; then
    echo "💾 Restoring original .env file..."
    mv .env.backup .env
  fi
  
  exit 0
else
  echo ""
  echo "❌ Password validation failed"
  exit 1
fi

