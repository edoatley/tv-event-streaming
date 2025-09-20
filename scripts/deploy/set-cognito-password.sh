#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Parameters ---
STACK_NAME="${1:-uktv-event-streaming-app}"
PROFILE="${2:-default}"
REGION="${3:-eu-west-2}"
NEW_PASSWORD="A-Strong-P@ssw0rd1"

echo "Fetching outputs from CloudFormation stack: $STACK_NAME..."

# Fetch all outputs in one go for efficiency
STACK_OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs" \
  --profile "$PROFILE" \
  --region "$REGION")

# Helper function to get a specific output value
get_output_value() {
    echo "$STACK_OUTPUTS" | jq -r ".[] | select(.OutputKey==\"$1\") | .OutputValue"
}

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

# --- Set User Passwords ---
USERS_TO_UPDATE=()
[ -n "$TEST_USERNAME" ] && USERS_TO_UPDATE+=("$TEST_USERNAME")
[ -n "$ADMIN_USERNAME" ] && USERS_TO_UPDATE+=("$ADMIN_USERNAME")

for USERNAME in "${USERS_TO_UPDATE[@]}"; do
  echo -e "\nSetting initial password for user: $USERNAME..."
  aws cognito-idp admin-set-user-password \
    --user-pool-id "$USER_POOL_ID" \
    --username "$USERNAME" \
    --password "$NEW_PASSWORD" \
    --permanent \
    --profile "$PROFILE" \
    --region "$REGION"
  echo "✅ Password for '$USERNAME' has been set."
done

echo -e "\nAll specified users have been updated. You can now log in."
