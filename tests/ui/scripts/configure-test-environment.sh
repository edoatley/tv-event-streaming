#!/bin/bash
# Script to configure test environment by fetching stack outputs and validating passwords
# Usage: ./configure-test-environment.sh <stack-name> [region] [profile]

set -e

STACK_NAME="${1:-tv-event-streaming-gha}"
REGION="${2:-eu-west-2}"
PROFILE="${3:-default}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

echo "🔧 Configuring Test Environment"
echo "================================"
echo "Stack Name: ${STACK_NAME}"
echo "Region: ${REGION}"
echo "Profile: ${PROFILE}"
echo ""

# Step 1: Fetch stack outputs and passwords
echo "📥 Step 1: Fetching stack outputs and passwords from Secrets Manager..."
./scripts/fetch-stack-outputs.sh "${STACK_NAME}" "${REGION}" "${PROFILE}"

if [ ! -f ".env" ]; then
  echo "❌ ERROR: .env file was not created"
  exit 1
fi

echo ""

# Step 2: Verify passwords were retrieved and are not empty
echo "🔍 Step 2: Verifying passwords were retrieved..."
TEST_PWD_LINE=$(grep "^TEST_USER_PASSWORD=" .env 2>/dev/null || echo "")
ADMIN_PWD_LINE=$(grep "^ADMIN_USER_PASSWORD=" .env 2>/dev/null || echo "")

if [ -z "$TEST_PWD_LINE" ] || [ -z "$ADMIN_PWD_LINE" ]; then
  echo "❌ ERROR: Passwords were not retrieved from Secrets Manager"
  echo "The pipeline should have created passwords and stored them in: ${STACK_NAME}/UserPasswords"
  echo ""
  echo "Current .env file contents (passwords redacted):"
  grep -E "^(TEST_USER|ADMIN_USER)" .env | sed 's/=.*/=***REDACTED***/' || echo "  No password lines found"
  exit 1
fi

# Extract password values (everything after =)
TEST_PWD_VALUE=$(echo "$TEST_PWD_LINE" | cut -d'=' -f2-)
ADMIN_PWD_VALUE=$(echo "$ADMIN_PWD_LINE" | cut -d'=' -f2-)

if [ -z "$TEST_PWD_VALUE" ] || [ "$TEST_PWD_VALUE" = "" ]; then
  echo "❌ ERROR: TEST_USER_PASSWORD is empty in .env file"
  exit 1
fi

if [ -z "$ADMIN_PWD_VALUE" ] || [ "$ADMIN_PWD_VALUE" = "" ]; then
  echo "❌ ERROR: ADMIN_USER_PASSWORD is empty in .env file"
  exit 1
fi

echo "✅ Passwords retrieved from Secrets Manager"
echo "  Test user password length: ${#TEST_PWD_VALUE} characters"
echo "  Admin user password length: ${#ADMIN_PWD_VALUE} characters"
echo ""

# Step 3: Verify passwords don't contain newlines or other problematic characters
echo "🔍 Step 3: Checking password format..."
if echo "$TEST_PWD_VALUE" | grep -q $'\n'; then
  echo "⚠️  Warning: TEST_USER_PASSWORD contains newlines, which may cause issues"
fi
if echo "$ADMIN_PWD_VALUE" | grep -q $'\n'; then
  echo "⚠️  Warning: ADMIN_USER_PASSWORD contains newlines, which may cause issues"
fi

echo "✅ Password format checks passed"
echo ""

# Step 4: Validate passwords by attempting authentication with Cognito
echo "🔐 Step 4: Validating passwords with Cognito authentication..."
./scripts/validate-passwords.sh ".env" "${REGION}" "${PROFILE}"

echo ""
echo "✅ Test environment configured successfully!"

