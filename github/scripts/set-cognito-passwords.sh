#!/bin/bash
# This script sets the passwords for the test and admin users in cognito
set -eou

# --- Parameters ---
TEST_USER_PASSWORD="$1"
ADMIN_USER_PASSWORD="$2"
STACK_NAME="${3:-uktv-event-streaming-app}"
REGION="${4:-eu-west-2}"

# Function to set a user's password
set_user_password() {
  local username_to_set="$1"
  local password_to_set="$2"
  echo -e "\nSetting initial password for user: $username_to_set..."
  aws cognito-idp admin-set-user-password \
    --user-pool-id "$USER_POOL_ID" \
    --username "$username_to_set" \
    --password "$password_to_set" \
    --permanent \
    --region "$REGION"
  echo "✅ Password for '$username_to_set' has been set."
}

# Helper function to get a specific output value
get_output_value() {
    echo "$STACK_OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"
}

echo "Fetching details from CloudFormation stack: $STACK_NAME..."
# Fetch all outputs in one go for efficiency
STACK_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs" \
  --region "$REGION")

# --- Fetch Required Values ---
USER_POOL_ID=$(get_output_value "UserPoolId")
TEST_USERNAME=$(get_output_value "TestUsername")
ADMIN_USERNAME=$(get_output_value "AdminUsername")

# --- Validation ---
if [ -z "$USER_POOL_ID" ]; then
    echo "Error: Could not retrieve User Pool ID. Please check if the stack '$STACK_NAME' exists."
    exit 1
fi

if [ -z "$TEST_USERNAME" ] && [ -z "$ADMIN_USERNAME" ]; then
    echo "Error: Could not retrieve any usernames from stack outputs."
    exit 1
fi

echo "✅ Stack outputs retrieved successfully!"
echo "   - User Pool ID: $USER_POOL_ID"
echo "   - Test username: $TEST_USERNAME"
echo "   - Admin username: $ADMIN_USERNAME"

echo "Setting user passwords..."
set_user_password "$TEST_USERNAME" "$TEST_USER_PASSWORD"
echo "✅ ${TEST_USERNAME} password set!"
set_user_password "$ADMIN_USERNAME" "$ADMIN_USER_PASSWORD"
echo "✅ ${ADMIN_USERNAME} password set!"

echo "✅ Passwords set."
