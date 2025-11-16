#!/bin/bash

# Script to build .env file from env.example, root .env, and CloudFormation outputs
# Usage: ./build-env.sh [stack-name] [region] [profile]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
ROOT_ENV_FILE="${PROJECT_ROOT}/.env"
TEST_ENV_FILE="${TEST_DIR}/.env"
TEST_ENV_EXAMPLE="${TEST_DIR}/env.example"

# Default values
STACK_NAME="${1:-tv-event-streaming-gha}"
REGION="${2:-eu-west-2}"
PROFILE="${3:-streaming}"

print_info() {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
  echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_warn() {
  echo -e "\033[1;33m[WARN]\033[0m $1"
}

print_error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_info "Building .env file for UI tests..."
print_info "Stack: ${STACK_NAME}"
print_info "Region: ${REGION}"
print_info "Profile: ${PROFILE}"

# Step 1: Create .env from env.example if it doesn't exist
if [ ! -f "${TEST_ENV_FILE}" ]; then
  if [ -f "${TEST_ENV_EXAMPLE}" ]; then
    print_info "Creating .env from env.example..."
    cp "${TEST_ENV_EXAMPLE}" "${TEST_ENV_FILE}"
    print_success "Created .env file"
  else
    print_error "env.example not found at ${TEST_ENV_EXAMPLE}"
    exit 1
  fi
else
  print_info ".env file already exists, will update values"
fi

# Step 2: Source values from root .env file if it exists
if [ -f "${ROOT_ENV_FILE}" ]; then
  print_info "Sourcing values from root .env file..."
  
  # Function to update or add a variable in .env file
  update_env_var_from_root() {
    local key="$1"
    local value="$2"
    
    if [ -z "$value" ]; then
      return  # Skip if value is empty
    fi
    
    # Escape special characters in value for sed
    local escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    if grep -q "^${key}=" "${TEST_ENV_FILE}" 2>/dev/null; then
      # Update existing variable
      if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|^${key}=.*|${key}=${escaped_value}|" "${TEST_ENV_FILE}"
      else
        # Linux
        sed -i "s|^${key}=.*|${key}=${escaped_value}|" "${TEST_ENV_FILE}"
      fi
      print_info "  Updated ${key}"
    else
      # Add new variable
      echo "${key}=${value}" >> "${TEST_ENV_FILE}"
      print_info "  Added ${key}"
    fi
  }
  
  # Read root .env and extract relevant variables
  # Handle both KEY=value and KEY="value" formats
  FOUND_VARS=0
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    
    # Extract key and value, handling quoted values
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      
      # Remove leading/trailing whitespace from key
      key=$(echo "$key" | xargs)
      
      # Remove quotes from value if present
      value=$(echo "$value" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' -e "s/^[[:space:]]*'//" -e "s/'[[:space:]]*$//" -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      
      # Update variables that are relevant for tests
      case "$key" in
        TEST_USER_PASSWORD|ADMIN_USER_PASSWORD|AWS_REGION|AWS_PROFILE)
          update_env_var_from_root "$key" "$value"
          FOUND_VARS=$((FOUND_VARS + 1))
          ;;
        # Also check for variations that might be in root .env
        TEST_USER_EMAIL|ADMIN_USER_EMAIL|COGNITO_USER_POOL_ID|COGNITO_CLIENT_ID|TEST_SCRIPT_USER_POOL_CLIENT_ID|BASE_URL|API_ENDPOINT)
          # Only update if not already set (will be updated later from CloudFormation if available)
          if ! grep -q "^${key}=" "${TEST_ENV_FILE}" 2>/dev/null; then
            update_env_var_from_root "$key" "$value"
            FOUND_VARS=$((FOUND_VARS + 1))
          fi
          ;;
      esac
    fi
  done < "${ROOT_ENV_FILE}"
  
  if [ $FOUND_VARS -eq 0 ]; then
    print_warn "No matching variables found in root .env file"
    print_info "Looking for: TEST_USER_PASSWORD, ADMIN_USER_PASSWORD, AWS_REGION, AWS_PROFILE"
  else
    print_info "Found and updated ${FOUND_VARS} variable(s) from root .env"
  fi
  
  print_success "Loaded values from root .env"
else
  print_warn "Root .env file not found at ${ROOT_ENV_FILE}"
fi

# Step 3: Fetch CloudFormation stack outputs
print_info "Fetching CloudFormation stack outputs..."

STACK_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs" \
  --profile "${PROFILE}" \
  --region "${REGION}" \
  2>/dev/null)

if [ $? -ne 0 ] || [ -z "$STACK_OUTPUTS" ]; then
  print_warn "Could not retrieve stack outputs. Continuing with existing .env values..."
  print_warn "You may need to manually set CloudFormation values in .env"
else
  # Helper function to get a specific output value
  get_output_value() {
    echo "$STACK_OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue" 2>/dev/null || echo ""
  }

  # Fetch required values from CloudFormation
  BASE_URL=$(get_output_value "WebsiteUrl")
  USER_POOL_ID=$(get_output_value "UserPoolId")
  USER_POOL_CLIENT_ID=$(get_output_value "UserPoolClientId")
  TEST_SCRIPT_CLIENT_ID=$(get_output_value "TestScriptUserPoolClientId")
  TEST_USERNAME=$(get_output_value "TestUsername")
  ADMIN_USERNAME=$(get_output_value "AdminUsername")
  API_ENDPOINT=$(get_output_value "WebApiEndpoint")
  ADMIN_API_ENDPOINT=$(get_output_value "AdminApiEndpoint")

  print_info "Retrieved CloudFormation values:"
  [ -n "$BASE_URL" ] && echo "  BASE_URL: ${BASE_URL}"
  [ -n "$USER_POOL_ID" ] && echo "  USER_POOL_ID: ${USER_POOL_ID}"
  [ -n "$USER_POOL_CLIENT_ID" ] && echo "  USER_POOL_CLIENT_ID: ${USER_POOL_CLIENT_ID}"
  [ -n "$TEST_SCRIPT_CLIENT_ID" ] && echo "  TEST_SCRIPT_CLIENT_ID: ${TEST_SCRIPT_CLIENT_ID}"
  [ -n "$TEST_USERNAME" ] && echo "  TEST_USERNAME: ${TEST_USERNAME}"
  [ -n "$ADMIN_USERNAME" ] && echo "  ADMIN_USERNAME: ${ADMIN_USERNAME}"

  # Function to update or add a variable in .env file
  update_env_var() {
    local key="$1"
    local value="$2"
    local comment="$3"
    
    if [ -z "$value" ]; then
      return  # Skip if value is empty
    fi
    
    # Escape special characters in value for sed
    local escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    if grep -q "^${key}=" "${TEST_ENV_FILE}" 2>/dev/null; then
      # Update existing variable
      if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|^${key}=.*|${key}=${escaped_value}|" "${TEST_ENV_FILE}"
      else
        # Linux
        sed -i "s|^${key}=.*|${key}=${escaped_value}|" "${TEST_ENV_FILE}"
      fi
    else
      # Add new variable (before any comments if possible)
      if [ -n "$comment" ]; then
        echo "# ${comment}" >> "${TEST_ENV_FILE}"
      fi
      echo "${key}=${escaped_value}" >> "${TEST_ENV_FILE}"
    fi
  }

  # Update .env file with CloudFormation values
  # Note: We don't update passwords here - those should come from root .env
  print_info "Updating .env file with CloudFormation values..."
  
  [ -n "$BASE_URL" ] && update_env_var "BASE_URL" "$BASE_URL" "Application URL from CloudFormation"
  [ -n "$USER_POOL_ID" ] && update_env_var "COGNITO_USER_POOL_ID" "$USER_POOL_ID" "Cognito User Pool ID from CloudFormation"
  [ -n "$USER_POOL_CLIENT_ID" ] && update_env_var "COGNITO_CLIENT_ID" "$USER_POOL_CLIENT_ID" "Cognito App Client ID from CloudFormation"
  [ -n "$TEST_SCRIPT_CLIENT_ID" ] && update_env_var "TEST_SCRIPT_USER_POOL_CLIENT_ID" "$TEST_SCRIPT_CLIENT_ID" "Test Script Client ID from CloudFormation"
  [ -n "$TEST_USERNAME" ] && update_env_var "TEST_USER_EMAIL" "$TEST_USERNAME" "Test user email from CloudFormation"
  [ -n "$ADMIN_USERNAME" ] && update_env_var "ADMIN_USER_EMAIL" "$ADMIN_USERNAME" "Admin user email from CloudFormation"
  [ -n "$API_ENDPOINT" ] && update_env_var "API_ENDPOINT" "$API_ENDPOINT" "API Gateway endpoint from CloudFormation"
  # Only update AWS_REGION and AWS_PROFILE if they weren't set from root .env
  if ! grep -q "^AWS_REGION=.*[^=]$" "${TEST_ENV_FILE}" 2>/dev/null || grep -q "^AWS_REGION=$" "${TEST_ENV_FILE}" 2>/dev/null; then
    [ -n "$REGION" ] && update_env_var "AWS_REGION" "$REGION" "AWS Region"
  fi
  if ! grep -q "^AWS_PROFILE=.*[^=]$" "${TEST_ENV_FILE}" 2>/dev/null || grep -q "^AWS_PROFILE=$" "${TEST_ENV_FILE}" 2>/dev/null; then
    [ -n "$PROFILE" ] && update_env_var "AWS_PROFILE" "$PROFILE" "AWS Profile"
  fi

  print_success "Updated .env file with CloudFormation values"
fi

# Step 4: Check for required values that might still be missing
print_info "Checking for required values..."

MISSING_VARS=()

# Check critical variables
if ! grep -q "^BASE_URL=.*[^=]$" "${TEST_ENV_FILE}" 2>/dev/null || grep -q "^BASE_URL=$" "${TEST_ENV_FILE}" 2>/dev/null; then
  MISSING_VARS+=("BASE_URL")
fi

if ! grep -q "^COGNITO_USER_POOL_ID=.*[^=]$" "${TEST_ENV_FILE}" 2>/dev/null || grep -q "^COGNITO_USER_POOL_ID=$" "${TEST_ENV_FILE}" 2>/dev/null; then
  MISSING_VARS+=("COGNITO_USER_POOL_ID")
fi

if ! grep -q "^TEST_SCRIPT_USER_POOL_CLIENT_ID=.*[^=]$" "${TEST_ENV_FILE}" 2>/dev/null || grep -q "^TEST_SCRIPT_USER_POOL_CLIENT_ID=$" "${TEST_ENV_FILE}" 2>/dev/null; then
  MISSING_VARS+=("TEST_SCRIPT_USER_POOL_CLIENT_ID")
fi

if ! grep -q "^TEST_USER_PASSWORD=.*[^=]$" "${TEST_ENV_FILE}" 2>/dev/null || grep -q "^TEST_USER_PASSWORD=$" "${TEST_ENV_FILE}" 2>/dev/null; then
  MISSING_VARS+=("TEST_USER_PASSWORD")
fi

if ! grep -q "^ADMIN_USER_PASSWORD=.*[^=]$" "${TEST_ENV_FILE}" 2>/dev/null || grep -q "^ADMIN_USER_PASSWORD=$" "${TEST_ENV_FILE}" 2>/dev/null; then
  MISSING_VARS+=("ADMIN_USER_PASSWORD")
fi

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  print_warn "The following required variables are missing or empty:"
  for var in "${MISSING_VARS[@]}"; do
    echo "  - ${var}"
  done
  print_info "Please set these values manually in ${TEST_ENV_FILE}"
  print_info "Passwords can be found in the root .env file or set during deployment"
else
  print_success "All required variables are set!"
fi

print_success "✅ .env file build complete!"
print_info ""
print_info "Location: ${TEST_ENV_FILE}"
print_info ""
print_info "Next steps:"
print_info "  1. Review the .env file and ensure all values are correct"
print_info "  2. Set TEST_USER_PASSWORD and ADMIN_USER_PASSWORD if not already set"
print_info "  3. Run tests: ./run-tests.sh"

