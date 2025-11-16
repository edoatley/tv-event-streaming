#!/bin/bash

# Script to fetch CloudFormation stack outputs and update .env file
# Usage: ./fetch-stack-outputs.sh <stack-name> [region] [profile]

set -e

STACK_NAME="${1:-tv-event-streaming-gha}"
REGION="${2:-eu-west-2}"
PROFILE="${3:-streaming}"
ENV_FILE="${4:-.env}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_PATH="${SCRIPT_DIR}/../${ENV_FILE}"

echo "Fetching outputs from CloudFormation stack: ${STACK_NAME}..."
echo "Region: ${REGION}"
echo "Profile: ${PROFILE}"

# Fetch all outputs
STACK_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs" \
  --profile "${PROFILE}" \
  --region "${REGION}" \
  2>/dev/null)

if [ $? -ne 0 ] || [ -z "$STACK_OUTPUTS" ]; then
  echo "Error: Could not retrieve stack outputs. Please check:"
  echo "  - Stack name: ${STACK_NAME}"
  echo "  - Region: ${REGION}"
  echo "  - AWS profile: ${PROFILE}"
  echo "  - AWS credentials are configured"
  exit 1
fi

# Helper function to get a specific output value
get_output_value() {
  echo "$STACK_OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"
}

# Fetch required values
BASE_URL=$(get_output_value "WebsiteUrl")
USER_POOL_ID=$(get_output_value "UserPoolId")
USER_POOL_CLIENT_ID=$(get_output_value "UserPoolClientId")
TEST_SCRIPT_CLIENT_ID=$(get_output_value "TestScriptUserPoolClientId")
TEST_USERNAME=$(get_output_value "TestUsername")
ADMIN_USERNAME=$(get_output_value "AdminUsername")

# Validate critical outputs
if [ -z "$BASE_URL" ] || [ -z "$USER_POOL_ID" ]; then
  echo "Error: Could not retrieve critical stack outputs (WebsiteUrl or UserPoolId)."
  exit 1
fi

echo ""
echo "Retrieved values:"
echo "  BASE_URL: ${BASE_URL}"
echo "  USER_POOL_ID: ${USER_POOL_ID}"
echo "  USER_POOL_CLIENT_ID: ${USER_POOL_CLIENT_ID}"
echo "  TEST_SCRIPT_CLIENT_ID: ${TEST_SCRIPT_CLIENT_ID}"
echo "  TEST_USERNAME: ${TEST_USERNAME}"
echo "  ADMIN_USERNAME: ${ADMIN_USERNAME}"
echo ""

# Check if .env file exists
if [ ! -f "${ENV_PATH}" ]; then
  echo "Creating .env file from template..."
  if [ -f "${SCRIPT_DIR}/../.env.example" ]; then
    cp "${SCRIPT_DIR}/../.env.example" "${ENV_PATH}"
  elif [ -f "${SCRIPT_DIR}/../env.example" ]; then
    cp "${SCRIPT_DIR}/../env.example" "${ENV_PATH}"
  else
    echo "Warning: .env.example or env.example not found. Creating empty .env file."
    touch "${ENV_PATH}"
  fi
fi

# Update .env file
echo "Updating ${ENV_PATH}..."

# Function to update or add a variable in .env file
update_env_var() {
  local key="$1"
  local value="$2"
  
  if grep -q "^${key}=" "${ENV_PATH}"; then
    # Update existing variable
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      sed -i '' "s|^${key}=.*|${key}=${value}|" "${ENV_PATH}"
    else
      # Linux
      sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_PATH}"
    fi
  else
    # Add new variable
    echo "${key}=${value}" >> "${ENV_PATH}"
  fi
}

# Update variables
[ -n "$BASE_URL" ] && update_env_var "BASE_URL" "$BASE_URL"
[ -n "$USER_POOL_ID" ] && update_env_var "COGNITO_USER_POOL_ID" "$USER_POOL_ID"
[ -n "$USER_POOL_CLIENT_ID" ] && update_env_var "COGNITO_CLIENT_ID" "$USER_POOL_CLIENT_ID"
[ -n "$TEST_SCRIPT_CLIENT_ID" ] && update_env_var "TEST_SCRIPT_USER_POOL_CLIENT_ID" "$TEST_SCRIPT_CLIENT_ID"
[ -n "$TEST_USERNAME" ] && update_env_var "TEST_USER_EMAIL" "$TEST_USERNAME"
[ -n "$ADMIN_USERNAME" ] && update_env_var "ADMIN_USER_EMAIL" "$ADMIN_USERNAME"
[ -n "$REGION" ] && update_env_var "AWS_REGION" "$REGION"
[ -n "$PROFILE" ] && update_env_var "AWS_PROFILE" "$PROFILE"

echo "✅ .env file updated successfully!"
echo ""
echo "Note: You still need to set TEST_USER_PASSWORD and ADMIN_USER_PASSWORD manually."
echo "These are not stored in CloudFormation outputs for security reasons."

