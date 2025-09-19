#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Parameters ---
STACK_NAME="${1:-uktv-event-streaming-app}"
PROFILE="${2:-default}"
REGION="${3:-eu-west-2}"
CONFIG_TEMPLATE_PATH="src/web/js/config.js"
GENERATED_CONFIG_PATH="src/web/js/generated-config.js"

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
USER_POOL_CLIENT_ID=$(get_output_value "UserPoolClientId")
COGNITO_DOMAIN=$(get_output_value "UserPoolDomain")
API_ENDPOINT=$(get_output_value "WebApiEndpoint")
ADMIN_API_ENDPOINT=$(get_output_value "AdminApiEndpoint")
WEBSITE_URL=$(get_output_value "WebsiteUrl")
WEBSITE_BUCKET=$(get_output_value "WebsiteBucket")

# --- Validation ---
if [ -z "$USER_POOL_ID" ] || [ -z "$COGNITO_DOMAIN" ]; then
    echo "Error: Could not retrieve critical stack outputs (UserPoolId or UserPoolDomain). Please check if the stack '$STACK_NAME' is deployed correctly."
    exit 1
fi

# The redirect URI must match what's configured in Cognito
REDIRECT_URI="${WEBSITE_URL}/index.html"

# --- Generate Config File ---
echo "Generating config file at: $GENERATED_CONFIG_PATH"

# Create a temporary file for sed to work with on both macOS and Linux
TMP_CONFIG=$(mktemp)
cp "$CONFIG_TEMPLATE_PATH" "$TMP_CONFIG"

sed -i.bak "s|__USER_POOL_ID__|${USER_POOL_ID}|g" "$TMP_CONFIG"
sed -i.bak "s|__USER_POOL_CLIENT_ID__|${USER_POOL_CLIENT_ID}|g" "$TMP_CONFIG"
sed -i.bak "s|__COGNITO_DOMAIN__|${COGNITO_DOMAIN}|g" "$TMP_CONFIG"
sed -i.bak "s|__API_ENDPOINT__|${API_ENDPOINT}|g" "$TMP_CONFIG"
sed -i.bak "s|__ADMIN_API_ENDPOINT__|${ADMIN_API_ENDPOINT}|g" "$TMP_CONFIG"
sed -i.bak "s|__REDIRECT_URI__|${REDIRECT_URI}|g" "$TMP_CONFIG"

mv "$TMP_CONFIG" "$GENERATED_CONFIG_PATH"
rm -f "${TMP_CONFIG}.bak"

echo "✅ Config file generated successfully."

# --- Sync to S3 ---
echo -e "\nSyncing web assets to S3 bucket: $WEBSITE_BUCKET..."

aws s3 sync src/web "s3://${WEBSITE_BUCKET}/" --delete --exclude "*.DS_Store*" --exclude "js/config.js" --profile "$PROFILE" --region "$REGION"

echo "✅ Website deployment complete!"
echo "You can access your application at: $WEBSITE_URL"
