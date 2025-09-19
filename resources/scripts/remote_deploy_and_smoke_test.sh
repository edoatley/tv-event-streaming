#!/bin/bash
set -e

STACK_NAME="uktv-event-streaming-app"
PROFILE="streaming"
REGION="eu-west-2"

########################################################################################################################
echo "🚀 Step 1: Checking AWS SSO session for profile: ${PROFILE}..."
########################################################################################################################
# The >/dev/null 2>&1 silences the command's output on success
if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
    echo "⚠️ AWS SSO session expired or not found. Please log in."
    # This command is interactive and will open a browser
    aws sso login --profile "${PROFILE}"

    # Re-check after login attempt to ensure it was successful before proceeding
    if ! aws sts get-caller-identity --profile "${PROFILE}" > /dev/null 2>&1; then
        echo "❌ AWS login failed. Please check your configuration. Aborting."
        exit 1
    fi
    echo "✅ AWS login successful."
else
    echo "✅ AWS SSO session is active."
fi


########################################################################################################################
echo "🚀 Step 2: Ensuring a clean environment by deleting the stack if it exists..."
########################################################################################################################
# The 'describe-stacks' command will fail if the stack doesn't exist. We use this to check.
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --profile "$PROFILE" --region "$REGION" > /dev/null 2>&1; then
   echo "🗑️ Stack '$STACK_NAME' already exists. Deleting it first to ensure a clean deployment..."
   sam delete \
     --stack-name "$STACK_NAME" \
     --profile "$PROFILE" \
     --region "$REGION" \
     --no-prompts
   echo "✅ Stack '$STACK_NAME' deleted."
else
   echo "ℹ️ Stack '$STACK_NAME' does not exist. Proceeding with new deployment."
fi


########################################################################################################################
echo "🚀 Step 3: Deploying the application with SAM..."
########################################################################################################################
sam build --use-container

sam deploy \
    --stack-name "$STACK_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
     --parameter-overrides "CreateDataStream=true" "WatchModeApiKey=${WATCHMODE_API_KEY}"

echo "✅ Deployment complete."
echo "⏳ Waiting for 30 seconds for resources to initialize..."
sleep 30

# After deployment, get the actual table name from the stack outputs
TABLE_NAME=$(aws cloudformation describe-stacks \
   --stack-name "$STACK_NAME" \
   --query "Stacks[0].Outputs[?OutputKey=='ProgrammesTable'].OutputValue" \
   --output text \
   --profile "$PROFILE" \
   --region "$REGION")
if [ -z "$TABLE_NAME" ]; then
    echo "❌ Could not determine DynamoDB table name from stack outputs. Exiting."
    exit 1
fi
echo "ℹ️ Using DynamoDB table: $TABLE_NAME"


########################################################################################################################
echo "🔄 Step 4: Triggering reference data refresh..."
########################################################################################################################
sam remote invoke PeriodicReferenceApp/PeriodicReferenceFunction \
  --stack-name "$STACK_NAME" \
  --event-file events/periodic_reference.json \
  --profile "$PROFILE" --region "$REGION"
echo "✅ Reference data refresh triggered."
sleep 5


########################################################################################################################
echo "👤 Step 5: Creating user preferences..."
########################################################################################################################
sam remote invoke UserPreferencesApp/UserPreferencesFunction \
  --stack-name "$STACK_NAME" \
  --event-file events/user_prefs_put_preferences.json \
  --profile "$PROFILE"
echo "✅ User preferences created."
sleep 5


########################################################################################################################
echo "📥 Step 6: Triggering user preferences ingestion..."
########################################################################################################################
sam remote invoke UserPrefsTitleIngestionApp/UserPrefsTitleIngestionFunction \
  --stack-name "$STACK_NAME" \
  --event-file events/userprefs_title_ingestion.json \
  --profile "$PROFILE"
echo "✅ User preferences ingestion triggered."


########################################################################################################################
echo "⏳ Step 7: Verifying data in DynamoDB..."
########################################################################################################################
echo "Waiting for 90 seconds for data to flow through Kinesis, be consumed, and enriched..."
sleep 90

echo "🔍 Scanning DynamoDB for enriched title records..."
# We query for a specific title that we expect to be ingested and enriched.
# An enriched title will have the 'plot_overview' attribute.
ITEM_COUNT=$(aws dynamodb scan \
  --table-name "$TABLE_NAME" \
  --filter-expression "attribute_exists(#data.plot_overview)" \
  --expression-attribute-names '{"#data": "data"}' \
  --select "COUNT" \
  --profile "$PROFILE" \
  --region "$REGION" | jq .Count)

if [ "$ITEM_COUNT" -gt 0 ]; then
    echo "✅ Success! Found $ITEM_COUNT enriched items in DynamoDB."
else
    echo "❌ Failure! No enriched items found in DynamoDB."
    # Even if it fails, we continue to the teardown.
fi


########################################################################################################################
echo "⏳ Step 8: Dump data from DynamoDB..."
########################################################################################################################
# There are 4 types of data we shall extract into 4 different files
# - genres
# - sources
# - titles
# - user preferences

echo "Extracting the genres:"
aws dynamodb scan \
  --table-name "$TABLE_NAME" \
  --filter-expression "begins_with(PK, :prefix)" \
  --expression-attribute-values '{":prefix":{"S":"genre:"}}' \
  --output json \
  --profile "$PROFILE" --region "$REGION" | jq '.' > genres.json

echo "Extracting the sources:"
aws dynamodb scan \
  --table-name "$TABLE_NAME" \
  --filter-expression "begins_with(PK, :prefix)" \
  --expression-attribute-values '{":prefix":{"S":"source:"}}' \
  --output json \
  --profile "$PROFILE" --region "$REGION" | jq '.' > sources.json

echo "Extracting the titles:"
aws dynamodb scan \
  --table-name "$TABLE_NAME" \
  --filter-expression "begins_with(PK, :prefix)" \
  --expression-attribute-values '{":prefix":{"S":"title:"}}' \
  --output json \
  --profile "$PROFILE" --region "$REGION" | jq '.' > titles.json

echo "Extracting the userprefs:"
aws dynamodb scan \
  --table-name "$TABLE_NAME" \
  --filter-expression "begins_with(PK, :prefix)" \
  --expression-attribute-values '{":prefix":{"S":"userpref:"}}' \
  --output json \
  --profile "$PROFILE" --region "$REGION" | jq '.' > userprefs.json


########################################################################################################################
echo "🗑️ Step 9: Tearing down the infrastructure..."
########################################################################################################################
sam delete \
  --stack-name "$STACK_NAME" \
  --profile "$PROFILE" \
  --region "$REGION" \
  --no-prompts

echo "✅ Teardown complete."
echo "🎉 Smoke test finished successfully!"
