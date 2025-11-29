#!/bin/bash
# This script deploys changes to the existing AWS stack for rapid development and testing.

set -e

STACK_NAME="uktv-event-streaming-app"
PROFILE="streaming"
REGION="eu-west-2"
SAM_DEPLOY_ARGS=()

# --- Argument Parsing ---
# Process command-line arguments and pass them to `sam deploy`.
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --disable-rollback)
            SAM_DEPLOY_ARGS+=("--disable-rollback")
            shift # past argument
            ;;
        *) echo "Unknown parameter passed: $1" >&2; exit 1 ;;
    esac
done

########################################################################################################################
echo "🚀 Step 1: Refreshing AWS SSO session for profile: ${PROFILE}..."
########################################################################################################################
echo "🔎 Checking AWS SSO session for profile: ${PROFILE}..."
if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null; then
   echo "⚠️ AWS SSO session expired or not found. Attempting to refresh..."
   aws sso login --profile "${PROFILE}"

   if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
       echo "❌ AWS login failed. Please check your configuration. Aborting."
       exit 1
   fi
   echo "✅ AWS login successful."
else
   echo "✅ AWS SSO session is active."
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "${PROFILE}")

# Navigate to the SAM project directory to ensure samconfig.toml is found
cd "$(dirname "$0")/../../"

########################################################################################################################
echo "🚀 Step 2: Checking stack status and cleaning up if necessary..."
########################################################################################################################
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].StackStatus" --output text --profile "$PROFILE" --region "$REGION" 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ] || [ "$STACK_STATUS" == "DELETE_FAILED" ]; then
    echo "🗑️ Stack is in a recoverable but failed state ($STACK_STATUS). Cleaning up before deployment..."

    WEBSITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='WebsiteBucket'].OutputValue" --output text --profile "$PROFILE" --region "$REGION" 2>/dev/null)

    if [ -z "$WEBSITE_BUCKET" ] || [ "$WEBSITE_BUCKET" == "None" ]; then
        echo "⚠️ Could not find WebsiteBucket in stack outputs. Constructing name manually."
        WEBSITE_BUCKET="${STACK_NAME}-website-${ACCOUNT_ID}"
    fi

    echo "🧹 Emptying S3 bucket: s3://${WEBSITE_BUCKET}..."
    if aws s3 ls "s3://${WEBSITE_BUCKET}" --profile "${PROFILE}" --region "$REGION" > /dev/null 2>&1; then
        aws s3 rm "s3://${WEBSITE_BUCKET}" --recursive --profile "${PROFILE}" --region "$REGION"
        aws s3api delete-bucket --bucket "${WEBSITE_BUCKET}" --profile "${PROFILE}" --region "$REGION"
        echo "✅ Bucket emptied and deleted to be safe."
    else
        echo "✅ Bucket does not exist or is already gone. No action needed."
    fi

    echo "🗑️ Deleting stack..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --profile "$PROFILE" --region "$REGION"
    echo "⏳ Waiting for stack to be deleted..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --profile "$PROFILE" --region "$REGION"
    echo "✅ Stack deleted."
elif [ "$STACK_STATUS" != "DOES_NOT_EXIST" ] && [ "$STACK_STATUS" != "CREATE_COMPLETE" ] && [ "$STACK_STATUS" != "UPDATE_COMPLETE" ] && [ "$STACK_STATUS" != "UPDATE_ROLLBACK_COMPLETE" ]; then
    echo "⚠️ Stack is in an unrecoverable state ($STACK_STATUS). Please check the AWS console. Aborting."
    exit 1
fi

########################################################################################################################
echo "🚀 Step 3: Building the application with SAM..."
########################################################################################################################
sam build --use-container

########################################################################################################################
echo "🚀 Step 4: Creating or updating WatchMode API Key Secret..."
########################################################################################################################
if [ -z "$WATCHMODE_API_KEY" ]; then
    echo "❌ Error: WATCHMODE_API_KEY environment variable is not set."
    echo "Please set it before running this script: export WATCHMODE_API_KEY='your-api-key-here'"
    exit 1
fi

SECRET_NAME="${STACK_NAME}/WatchModeApiKey"

# Check if secret exists
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
    echo "📝 Updating existing secret: $SECRET_NAME"
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$WATCHMODE_API_KEY" \
        --profile "$PROFILE" \
        --region "$REGION"
else
    echo "📝 Creating new secret: $SECRET_NAME"
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "WatchMode API key for stack $STACK_NAME" \
        --secret-string "$WATCHMODE_API_KEY" \
        --profile "$PROFILE" \
        --region "$REGION"
fi

# Get the secret ARN
WATCHMODE_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --profile "$PROFILE" --region "$REGION" --query "ARN" --output text)
echo "✅ Secret created/updated: $WATCHMODE_SECRET_ARN"

########################################################################################################################
echo "🚀 Step 5: Deploying changes to the stack '$STACK_NAME'..."
########################################################################################################################
sam deploy \
    --stack-name "$STACK_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides "CreateDataStream=true" "WatchModeApiKeySecretArn=${WATCHMODE_SECRET_ARN}" \
    "${SAM_DEPLOY_ARGS[@]}"

echo "✅ Deployment complete. Your changes are now live."

########################################################################################################################
echo "🚀 Step 6: Setting passwords for Cognito users..."
########################################################################################################################
# Get password from environment variable or Secrets Manager
USER_PASSWORD="${PASSWORD:-}"
if [ -z "$USER_PASSWORD" ]; then
    echo "🔐 Attempting to fetch password from Secrets Manager..."
    SECRET_NAME="${STACK_NAME}/UserPasswords"
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1; then
        echo "Found secret in Secrets Manager, retrieving password..."
        USER_PASSWORDS_JSON=$(aws secretsmanager get-secret-value \
            --secret-id "$SECRET_NAME" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query "SecretString" \
            --output text)
        
        if [ -n "$USER_PASSWORDS_JSON" ] && [ "$USER_PASSWORDS_JSON" != "None" ]; then
            # Get the first password from the JSON (for setting both users to same password)
            USER_PASSWORD=$(echo "$USER_PASSWORDS_JSON" | jq -r 'to_entries[0].value // empty')
            if [ -z "$USER_PASSWORD" ] || [ "$USER_PASSWORD" == "null" ]; then
                echo "⚠️  Warning: Could not extract password from Secrets Manager"
            fi
        fi
    fi
fi

if [ -z "$USER_PASSWORD" ]; then
    echo "⚠️  Warning: Password not set via PASSWORD environment variable or Secrets Manager."
    echo "Skipping password setting. Users may need to reset passwords manually."
else
    echo "🏃 Running password setting script..."
    ./scripts/deploy/set-cognito-password.sh "$USER_PASSWORD" "$STACK_NAME" "$PROFILE" "$REGION"
    echo "✅ Passwords set."
fi

# Fetch outputs to display to the user
WEBSITE_URL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='WebsiteUrl'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")
TEST_USERNAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='TestUsername'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")
ADMIN_USERNAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='AdminUsername'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")

echo ""
echo "🎉 Deployment complete! You can now log in to the application:"
echo "--------------------------------------------------"
echo "Website URL:  $WEBSITE_URL"
echo "Test User:    $TEST_USERNAME"
echo "Admin User:   $ADMIN_USERNAME"
if [ -n "$USER_PASSWORD" ]; then
    echo "Password:     [Set via Secrets Manager or PASSWORD env var]"
else
    echo "Password:     [Not set - check Secrets Manager or set PASSWORD env var]"
fi
echo "--------------------------------------------------"

########################################################################################################################
echo "↔ Step 7: Updating website configuration and syncing to S3..."
########################################################################################################################
echo "🏃 Running website configuration script..."
# This script generates the config file and syncs all web assets to S3.
./resources/scripts/update_website_config.sh "$STACK_NAME" "$PROFILE" "$REGION"
echo "✅ Website configuration and sync complete."

########################################################################################################################
echo "🧹 Step 8: Clearing the CloudFront cache..."
########################################################################################################################
DISTRIBUTION_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='WebsiteDistributionId'].OutputValue" --output text --profile "$PROFILE" --region "$REGION")
if [ -z "$DISTRIBUTION_ID" ]; then
    echo "❌ Could not retrieve CloudFront Distribution ID from stack outputs. Aborting cache clear."
    exit 1
fi

aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*" --profile "$PROFILE" --region "$REGION" | jq
echo "✅ CloudFront cache invalidation created. Changes will be live shortly."
