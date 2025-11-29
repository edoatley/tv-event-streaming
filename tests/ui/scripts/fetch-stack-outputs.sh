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

# Build AWS CLI profile argument - only use profile if not in CI (GitHub Actions sets CI=true)
# and profile is not "default"
AWS_PROFILE_ARG=""
if [ -z "${CI:-}" ] && [ "${PROFILE}" != "default" ] && [ -n "${PROFILE}" ]; then
  AWS_PROFILE_ARG="--profile ${PROFILE}"
fi

# Fetch all outputs
STACK_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs" \
  ${AWS_PROFILE_ARG} \
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
USER_PASSWORDS_JSON=$(get_output_value "UserPasswords")

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
# Properly handles special characters in values by rewriting the entire file
update_env_var() {
  local key="$1"
  local value="$2"
  local temp_file=$(mktemp)
  local key_found=false
  
  # Read the existing .env file line by line and update or add the variable
  while IFS= read -r line || [ -n "$line" ]; do
    # Check if this line is the variable we're updating
    if [[ "$line" =~ ^${key}= ]]; then
      # Update the existing line
      printf '%s=%s\n' "${key}" "${value}" >> "${temp_file}"
      key_found=true
    else
      # Keep the original line
      echo "$line" >> "${temp_file}"
    fi
  done < "${ENV_PATH}" 2>/dev/null || true
  
  # If the key wasn't found, add it at the end
  if [ "$key_found" = false ]; then
    printf '%s=%s\n' "${key}" "${value}" >> "${temp_file}"
  fi
  
  # Replace the original file with the updated one
  mv "${temp_file}" "${ENV_PATH}"
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

# Extract passwords - prioritize Secrets Manager (where pipeline stores them), then fallback to stack outputs
# Check if passwords are already set in .env
TEST_PASSWORD_EXISTS=$(grep -q "^TEST_USER_PASSWORD=" "${ENV_PATH}" 2>/dev/null && echo "yes" || echo "no")
ADMIN_PASSWORD_EXISTS=$(grep -q "^ADMIN_USER_PASSWORD=" "${ENV_PATH}" 2>/dev/null && echo "yes" || echo "no")

# Primary source: Secrets Manager (where the pipeline stores passwords)
if [ "$TEST_PASSWORD_EXISTS" = "no" ] || [ "$ADMIN_PASSWORD_EXISTS" = "no" ]; then
  SECRET_NAME="${STACK_NAME}/UserPasswords"
  
  # Retry logic for secret retrieval (handles eventual consistency)
  MAX_RETRIES=5
  RETRY_COUNT=0
  SECRET_PASSWORDS_JSON=""
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" ${AWS_PROFILE_ARG} --region "${REGION}" >/dev/null 2>&1; then
      echo "  Fetching passwords from Secrets Manager: $SECRET_NAME (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
      SECRET_PASSWORDS_JSON=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_NAME" \
        ${AWS_PROFILE_ARG} \
        --region "${REGION}" \
        --query "SecretString" \
        --output text 2>/dev/null || echo "")
      
      if [ -n "$SECRET_PASSWORDS_JSON" ] && [ "$SECRET_PASSWORDS_JSON" != "null" ] && [ "$SECRET_PASSWORDS_JSON" != "None" ]; then
        # Verify it's valid JSON
        if echo "$SECRET_PASSWORDS_JSON" | jq -e . >/dev/null 2>&1; then
          break
        else
          echo "  ⚠️  Warning: Secret value is not valid JSON, retrying..."
          SECRET_PASSWORDS_JSON=""
        fi
      fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      sleep 2
    fi
  done
  
  if [ -n "$SECRET_PASSWORDS_JSON" ] && [ "$SECRET_PASSWORDS_JSON" != "null" ] && [ "$SECRET_PASSWORDS_JSON" != "None" ]; then
    if [ "$TEST_PASSWORD_EXISTS" = "no" ] && [ -n "$TEST_USERNAME" ]; then
      TEST_USER_PASSWORD=$(echo "$SECRET_PASSWORDS_JSON" | jq -r ".[\"$TEST_USERNAME\"]" 2>/dev/null || echo "")
      if [ -n "$TEST_USER_PASSWORD" ] && [ "$TEST_USER_PASSWORD" != "null" ] && [ "$TEST_USER_PASSWORD" != "" ]; then
        update_env_var "TEST_USER_PASSWORD" "$TEST_USER_PASSWORD"
        echo "  ✅ Extracted TEST_USER_PASSWORD from Secrets Manager for user: $TEST_USERNAME"
        echo "     Password length: ${#TEST_USER_PASSWORD} characters"
      else
        echo "  ❌ ERROR: Could not extract TEST_USER_PASSWORD from Secrets Manager for user: $TEST_USERNAME"
        echo "     Secret JSON keys: $(echo "$SECRET_PASSWORDS_JSON" | jq -r 'keys | join(", ")' 2>/dev/null || echo "unknown")"
      fi
    fi
    
    if [ "$ADMIN_PASSWORD_EXISTS" = "no" ] && [ -n "$ADMIN_USERNAME" ]; then
      ADMIN_USER_PASSWORD=$(echo "$SECRET_PASSWORDS_JSON" | jq -r ".[\"$ADMIN_USERNAME\"]" 2>/dev/null || echo "")
      if [ -n "$ADMIN_USER_PASSWORD" ] && [ "$ADMIN_USER_PASSWORD" != "null" ] && [ "$ADMIN_USER_PASSWORD" != "" ]; then
        update_env_var "ADMIN_USER_PASSWORD" "$ADMIN_USER_PASSWORD"
        echo "  ✅ Extracted ADMIN_USER_PASSWORD from Secrets Manager for user: $ADMIN_USERNAME"
        echo "     Password length: ${#ADMIN_USER_PASSWORD} characters"
      else
        echo "  ❌ ERROR: Could not extract ADMIN_USER_PASSWORD from Secrets Manager for user: $ADMIN_USERNAME"
        echo "     Secret JSON keys: $(echo "$SECRET_PASSWORDS_JSON" | jq -r 'keys | join(", ")' 2>/dev/null || echo "unknown")"
      fi
    fi
  else
    echo "  ⚠️  Warning: Could not retrieve secret from Secrets Manager after $MAX_RETRIES attempts"
    echo "     Secret name: $SECRET_NAME"
  fi
fi
  
  # Fallback: Try stack outputs (for backward compatibility with older deployments)
  TEST_PASSWORD_EXISTS=$(grep -q "^TEST_USER_PASSWORD=" "${ENV_PATH}" 2>/dev/null && echo "yes" || echo "no")
  ADMIN_PASSWORD_EXISTS=$(grep -q "^ADMIN_USER_PASSWORD=" "${ENV_PATH}" 2>/dev/null && echo "yes" || echo "no")
  
  if [ "$TEST_PASSWORD_EXISTS" = "no" ] || [ "$ADMIN_PASSWORD_EXISTS" = "no" ]; then
    if [ -n "$USER_PASSWORDS_JSON" ] && [ "$USER_PASSWORDS_JSON" != "null" ] && [ "$USER_PASSWORDS_JSON" != "None" ]; then
      # Extract passwords from stack outputs (legacy support)
      if [ "$TEST_PASSWORD_EXISTS" = "no" ] && [ -n "$TEST_USERNAME" ]; then
        TEST_USER_PASSWORD=$(echo "$USER_PASSWORDS_JSON" | jq -r ".[\"$TEST_USERNAME\"]" 2>/dev/null || echo "")
        if [ -n "$TEST_USER_PASSWORD" ] && [ "$TEST_USER_PASSWORD" != "null" ]; then
          update_env_var "TEST_USER_PASSWORD" "$TEST_USER_PASSWORD"
          echo "  Extracted TEST_USER_PASSWORD from stack outputs (legacy)"
        fi
      fi
      
      if [ "$ADMIN_PASSWORD_EXISTS" = "no" ] && [ -n "$ADMIN_USERNAME" ]; then
        ADMIN_USER_PASSWORD=$(echo "$USER_PASSWORDS_JSON" | jq -r ".[\"$ADMIN_USERNAME\"]" 2>/dev/null || echo "")
        if [ -n "$ADMIN_USER_PASSWORD" ] && [ "$ADMIN_USER_PASSWORD" != "null" ]; then
          update_env_var "ADMIN_USER_PASSWORD" "$ADMIN_USER_PASSWORD"
          echo "  Extracted ADMIN_USER_PASSWORD from stack outputs (legacy)"
        fi
      fi
    fi
  fi
fi

echo "✅ .env file updated successfully!"
echo ""
# Check if passwords are set
TEST_PASSWORD_SET=$(grep -q "^TEST_USER_PASSWORD=.*[^=]$" "${ENV_PATH}" 2>/dev/null && echo "yes" || echo "no")
ADMIN_PASSWORD_SET=$(grep -q "^ADMIN_USER_PASSWORD=.*[^=]$" "${ENV_PATH}" 2>/dev/null && echo "yes" || echo "no")

if [ "$TEST_PASSWORD_SET" = "no" ] || [ "$ADMIN_PASSWORD_SET" = "no" ]; then
  echo "⚠️  Note: TEST_USER_PASSWORD and/or ADMIN_USER_PASSWORD may need to be set manually."
  echo "Passwords were attempted to be extracted from Secrets Manager (primary) or stack outputs (fallback)."
  echo "The pipeline should create passwords and store them in Secrets Manager: ${STACK_NAME}/UserPasswords"
fi

